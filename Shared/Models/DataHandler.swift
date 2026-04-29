import Foundation
import OSLog
import SwiftUI

// MARK: - File-Based Data Structures
struct DeviceListData: Codable {
    var devices: [String] // Array of device UDNs in order

    init(devices: [String] = []) {
        self.devices = devices
    }
}

// MARK: - Registration System
typealias RegistrationToken = UUID

enum ChangeOperation: Hashable {
    case updateAppIcon(deviceId: String, appId: String)
    case updateDeviceList
    case updateHiddenDeviceList
    case updatePrimaryDevice
    case updatePrimaryApps
    case updateDevice(deviceId: String)
    case updateDeviceApps(deviceId: String)
    case updateMessages
}

struct RegistrationListenerRef {
    weak var listener: (any RegistrationListener)?
}

@MainActor
protocol RegistrationListener: AnyObject, Sendable {
    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String)
    func deviceDetailUpdated(for deviceId: String, device: Device?)
    func deviceListUpdated(devices: [String])
    func hiddenDeviceListUpdated(devices: [String])
    func primaryDeviceUpdated(device: Device?)
    func primaryAppsUpdated(apps: [AppLink]?)
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink])
    func messagesUpdated(messages: [Message], unreadCount: Int)
}

@MainActor
extension RegistrationListener {
    func messagesUpdated(messages: [Message], unreadCount: Int) { }
}

// MARK: - Main Data Handler
actor RoamDataHandler {
    private static let pendingMessageRetryDelay: TimeInterval = 30
    private static let discordNonceMaxLength = 25
    private static let persistentDatabaseRetryDelay: UInt64 = 30_000_000_000

#if DEBUG
    private static let debugDatabaseStartupOpenCountKey = "debugDatabaseStartupOpenCount"

    private struct DebugStartupDatabaseFault {
        enum Stage {
            case persistent
            case volatile

            var logName: String {
                switch self {
                case .persistent:
                    return "persistent"
                case .volatile:
                    return "volatile"
                }
            }
        }

        let stage: Stage
        let error: DataHandlerError
    }
#endif

    private var database: RoamDatabase
    private let persistentDatabaseURL: URL?
    private let persistentLockURL: URL?
    private let legacyRootPath: String?
    private var shouldRetryPersistentOpen: Bool
    private var persistentRetryTask: Task<Void, Never>?
    private var updateListeners: [RegistrationToken: RegistrationListenerRef] = [:]
    private var updateRegistrations: [ChangeOperation: Set<RegistrationToken>] = [:]

    // Cache storage
    private var cachedDeviceData: [String: Device] = [:]
    private var cachedDeviceApps: [String: [AppLink]] = [:]
    private var cachedDeviceList: [String]?
    private var cachedHiddenDeviceList: [String]?
    private var cachedPrimaryDevice: Device?
    private var cachedPrimaryApps: [AppLink]?
    private var cachedMessages: [Message]?
    private var cachedUnreadMessageCount: Int?
    private var isSendingPendingMessages = false

    @MainActor
    private static let _shared: RoamDataHandler? = getForShared()

    @MainActor
    static func sharedChecked() throws -> RoamDataHandler {
        guard let shared = _shared else {
            throw DataHandlerError.noContainerURL
        }
        return shared
    }

    @MainActor
    static var shared: RoamDataHandler {
        guard let shared = _shared else {
            loggedFatalError("No container url for main app group \(mainAppGroup)")
        }
        return shared
    }

    private init(
        database: RoamDatabase,
        persistentDatabaseURL: URL?,
        persistentLockURL: URL?,
        legacyRootPath: String?,
        shouldRetryPersistentOpen: Bool = false
    ) {
        self.database = database
        self.persistentDatabaseURL = persistentDatabaseURL
        self.persistentLockURL = persistentLockURL
        self.legacyRootPath = legacyRootPath
        self.shouldRetryPersistentOpen = shouldRetryPersistentOpen
        self.database.onExternalChange = { [weak self] in
            Task {
                await self?.handleExternalDatabaseChange()
            }
        }
        Task {
            await self.preloadDeviceList()
            await self.preloadPrimaryDevice()
            await self.preloadPrimaryApps()
            await self.preloadMessages()
            await self.startPersistentRetryLoopIfNeeded()
        }
    }

    deinit {
        persistentRetryTask?.cancel()
    }

    private static func getForShared() -> Self? {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup)
        guard let containerURL else {
            Log.backend.error("Failed to get app group container URL")
            return makeVolatileShared(
                persistentDatabaseURL: nil,
                persistentLockURL: nil,
                legacyRootPath: nil,
                error: .noContainerURL)
        }
        print("Getting container url \(containerURL)")
        let rootPath = containerURL.appendingPathComponent("rootData").path(percentEncoded: false)
        let databaseURL = containerURL.appendingPathComponent("Roam.sqlite")
        let lockURL = containerURL.appendingPathComponent(".Roam.sqlite.lock")
#if DEBUG
        let debugStartupFault = debugStartupDatabaseFaultIfNeeded()
#endif
        do {
#if DEBUG
            if let debugStartupFault {
                Log.backend.warning(
                    "DEBUG injecting \(debugStartupFault.stage.logName, privacy: .public) database startup fault: \(debugStartupFault.error.localizedDescription, privacy: .public)"
                )
                throw debugStartupFault.error
            }
#endif
            let database = try RoamDatabase(databaseURL: databaseURL, lockURL: lockURL, legacyRootPath: rootPath)
            return self.init(
                database: database,
                persistentDatabaseURL: databaseURL,
                persistentLockURL: lockURL,
                legacyRootPath: rootPath)
        } catch {
            let dataError = DataHandlerError.from(error: error)
            Log.backend.error("Failed to open Roam database: \(dataError, privacy: .public)")
#if DEBUG
            if debugStartupFault?.stage == .volatile {
                return makeVolatileShared(
                    persistentDatabaseURL: databaseURL,
                    persistentLockURL: lockURL,
                    legacyRootPath: rootPath,
                    error: dataError,
                    debugVolatileStartupError: debugStartupFault?.error)
            }
#endif
            return makeVolatileShared(
                persistentDatabaseURL: databaseURL,
                persistentLockURL: lockURL,
                legacyRootPath: rootPath,
                error: dataError)
        }
    }

    private static func makeVolatileShared(
        persistentDatabaseURL: URL?,
        persistentLockURL: URL?,
        legacyRootPath: String?,
        error: DataHandlerError,
        debugVolatileStartupError: DataHandlerError? = nil
    ) -> Self? {
        do {
#if DEBUG
            if let debugVolatileStartupError {
                Log.backend.warning(
                    "DEBUG injecting volatile database startup fault: \(debugVolatileStartupError.localizedDescription, privacy: .public)"
                )
                throw debugVolatileStartupError
            }
#endif
            let database = try RoamDatabase.openVolatile()
            let issue = DatabaseStatusIssue(error: error, isVolatile: true, operation: .open)
            Task { @MainActor in
                DatabaseStatusMonitor.shared.setIssue(issue)
            }
            return self.init(
                database: database,
                persistentDatabaseURL: persistentDatabaseURL,
                persistentLockURL: persistentLockURL,
                legacyRootPath: legacyRootPath,
                shouldRetryPersistentOpen: issue.isRetryable)
        } catch {
            Log.backend.error("Failed to open volatile Roam database: \(error, privacy: .public)")
            Task { @MainActor in
                DatabaseStatusMonitor.shared.setIssue(DatabaseStatusIssue(
                    error: DataHandlerError.from(error: error),
                    isVolatile: false,
                    operation: .open))
            }
            return nil
        }
    }

#if DEBUG
    private static func debugStartupDatabaseFaultIfNeeded() -> DebugStartupDatabaseFault? {
        let defaults = UserDefaults.standard
        let openCount = defaults.integer(forKey: debugDatabaseStartupOpenCountKey) + 1
        defaults.set(openCount, forKey: debugDatabaseStartupOpenCountKey)

        guard openCount % 5 == 0 else {
            return nil
        }

        let errors: [DataHandlerError] = [
            .noSpaceOnDisk,
            .databaseLocked,
            .databaseReadOnly,
            .databasePermissionDenied,
            .databaseCorrupt,
            .unknown,
        ]
        return DebugStartupDatabaseFault(
            stage: Bool.random() ? .persistent : .volatile,
            error: errors.randomElement() ?? .unknown
        )
    }
#endif

    private func configureDatabaseCallbacks() {
        database.onExternalChange = { [weak self] in
            Task {
                await self?.handleExternalDatabaseChange()
            }
        }
    }

    private func startPersistentRetryLoopIfNeeded() {
        guard !database.isPersistent,
              persistentDatabaseURL != nil,
              persistentRetryTask == nil,
              shouldRetryPersistentOpen
        else {
            return
        }

        persistentRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.persistentDatabaseRetryDelay)
                } catch {
                    return
                }
                await self?.retryOpeningPersistentDatabase()
            }
        }
    }

    func retryOpeningPersistentDatabase() {
        guard shouldRetryPersistentOpen else {
            persistentRetryTask?.cancel()
            persistentRetryTask = nil
            return
        }

        guard !database.isPersistent,
              let persistentDatabaseURL,
              let persistentLockURL
        else {
            persistentRetryTask?.cancel()
            persistentRetryTask = nil
            return
        }

        let volatileSnapshot = database.exportSnapshot()

        do {
            let persistentDatabase = try RoamDatabase(
                databaseURL: persistentDatabaseURL,
                lockURL: persistentLockURL,
                legacyRootPath: legacyRootPath)
            try persistentDatabase.mergeVolatileSnapshot(volatileSnapshot)
            database = persistentDatabase
            configureDatabaseCallbacks()
            handleExternalDatabaseChange()
            persistentRetryTask?.cancel()
            persistentRetryTask = nil
            shouldRetryPersistentOpen = false
            Task { @MainActor in
                DatabaseStatusMonitor.shared.clearIssue()
            }
            Log.backend.notice("Reopened persistent Roam database")
        } catch {
            let dataError = DataHandlerError.from(error: error)
            Task { @MainActor in
                DatabaseStatusMonitor.shared.setIssue(DatabaseStatusIssue(
                    error: dataError,
                    isVolatile: true,
                    operation: .open))
            }
            shouldRetryPersistentOpen = DatabaseStatusIssue(
                error: dataError,
                isVolatile: true,
                operation: .open
            ).isRetryable
            Log.backend.warning("Persistent Roam database retry failed: \(dataError, privacy: .public)")
        }
    }

    // MARK: - Request Functions
    func requestDeviceList() -> [String] {
        if let cachedDeviceList { return cachedDeviceList }

        do {
            let devices = try loadDeviceListFromDisk()
            cachedDeviceList = devices
            notifyDeviceListUpdated(devices: devices)
            return devices
        } catch {
            Log.data.error("Error loading device list: \(error, privacy: .public)")
            cachedDeviceList = []
            notifyDeviceListUpdated(devices: [])
            return []
        }
    }

    func requestHiddenDeviceList() -> [String] {
        if let cachedHiddenDeviceList { return cachedHiddenDeviceList }

        do {
            let devices = try loadHiddenDeviceListFromDisk()
            cachedHiddenDeviceList = devices
            notifyHiddenDeviceListUpdated(devices: devices)
            return devices
        } catch {
            Log.data.error("Error loading hidden device list: \(error, privacy: .public)")
            cachedHiddenDeviceList = []
            notifyHiddenDeviceListUpdated(devices: [])
            return []
        }
    }

    func requestDevice(id: String) -> Device? {
        if let d = cachedDeviceData[id] { return d }

        do {
            let device = try loadDeviceFromDisk(id: id)
            cachedDeviceData[id] = device
            notifyDeviceUpdated(deviceId: id, device: device)
            return device
        } catch {
            Log.data.error("Error loading device \(id, privacy: .public): \(error, privacy: .public)")
            notifyDeviceUpdated(deviceId: id, device: nil)
            return nil
        }
    }

    func requestDeviceApps(deviceId: String) -> [AppLink] {
        if let a = cachedDeviceApps[deviceId] { return a }

        do {
            let apps = try loadDeviceAppsFromDisk(deviceId: deviceId)
            cachedDeviceApps[deviceId] = apps
            notifyDeviceAppsUpdated(deviceId: deviceId, apps: apps)
            return apps
        } catch {
            Log.data.error("Error loading device apps \(deviceId, privacy: .public): \(error, privacy: .public)")
            cachedDeviceApps[deviceId] = []
            notifyDeviceAppsUpdated(deviceId: deviceId, apps: [])
            return []
        }
    }

    private func requestDeviceAppIcon(deviceId: String, appId: String)  {
        let apps = requestDeviceApps(deviceId: deviceId)
        guard let iconHash = apps.first(where: { $0.id == appId })?.iconHash else {
            return
        }
        notifyAppIconUpdated(deviceId: deviceId, appId: appId, iconDataHash: iconHash)
    }

    func requestPrimaryDevice() -> Device? {
        if let cachedPrimaryDevice { return cachedPrimaryDevice }

        do {
            let device = try loadPrimaryDeviceFromDisk()
            cachedPrimaryDevice = device
            if let device = device {
                cachedDeviceData[device.id] = device
            }
            notifyPrimaryDeviceUpdated(device: device)
            return device
        } catch {
            Log.data.error("Error loading primary device: \(error, privacy: .public)")
            notifyPrimaryDeviceUpdated(device: nil)
            return nil
        }
    }

    private func requestPrimaryApps() -> [AppLink] {
        if let cachedPrimaryApps { return cachedPrimaryApps }

        do {
            let apps = try loadPrimaryAppsFromDisk()
            cachedPrimaryApps = apps
            notifyPrimaryAppsUpdated(apps: apps)
            return apps ?? []
        } catch {
            Log.data.error("Error loading primary apps: \(error, privacy: .public)")
            cachedPrimaryApps = []
            notifyPrimaryAppsUpdated(apps: [])
            return []
        }
    }

    func requestMessages() -> [Message] {
        if let cachedMessages { return cachedMessages }

        let messages = database.messages()
        cachedMessages = messages
        cachedUnreadMessageCount = database.unreadMessageCount()
        notifyMessagesUpdated(messages: messages, unreadCount: cachedUnreadMessageCount ?? 0)
        return messages
    }

    func requestUnreadMessageCount() -> Int {
        if let cachedUnreadMessageCount { return cachedUnreadMessageCount }

        let unreadCount = database.unreadMessageCount()
        cachedUnreadMessageCount = unreadCount
        return unreadCount
    }

    func requestAllDevices(_ deviceIds: [String]) async -> [Device] {
        var devices: [Device] = []

        for deviceId in deviceIds {
            // Check cache first
            if let cachedDevice = cachedDeviceData[deviceId] {
                devices.append(cachedDevice)
                continue
            }

            do {
                if let device = try loadDeviceFromDisk(id: deviceId) {
                    cachedDeviceData[deviceId] = device

                    self.notifyDeviceUpdated(deviceId: deviceId, device: device)

                    devices.append(device)
                }
            } catch {
                Log.data.error("Failed to load device \(deviceId, privacy: .public): \(error, privacy: .public)")
            }
        }

        return devices
    }

    // MARK: - Public Data Loader Factory Functions
    @MainActor
    func deviceListLoader() -> DeviceListLoader {
        let loader = DeviceListLoader(dataHandler: self)
        Task {
            await self.requestDeviceList()
        }
        return loader
    }

    @MainActor
    func hiddenDeviceListLoader() -> HiddenDeviceListLoader {
        let loader = HiddenDeviceListLoader(dataHandler: self)
        Task {
            await self.requestHiddenDeviceList()
        }
        return loader
    }

    @MainActor
    func deviceLoader(id: String) -> DeviceLoader {
        let loader = DeviceLoader(deviceId: id, dataHandler: self)
        Task {
            await self.requestDevice(id: id)
        }
        return loader
    }

    @MainActor
    func deviceAppsLoader(deviceId: String) -> DeviceAppsLoader {
        let loader = DeviceAppsLoader(deviceId: deviceId, dataHandler: self)
        Task {
            await self.requestDeviceApps(deviceId: deviceId)
        }
        return loader
    }

    @MainActor
    func deviceAppIconLoader(deviceId: String, appId: String) -> DeviceAppIconLoader {
        let loader = DeviceAppIconLoader(deviceId: deviceId, appId: appId, dataHandler: self)
        Task {
            await self.requestDeviceAppIcon(deviceId: deviceId, appId: appId)
        }
        return loader
    }

    @MainActor
    func primaryDeviceLoader() -> PrimaryDeviceLoader {
        let loader = PrimaryDeviceLoader(dataHandler: self)
        Task {
            await self.requestPrimaryDevice()
        }
        return loader
    }

    // MARK: - Public Update Functions
    func addDevice(location: String, friendlyDeviceName: String, udn: String, serial: String, hidden: Bool = false) async throws -> String {
        let device = Device(
            name: friendlyDeviceName,
            location: location,
            udn: udn,
            serial: serial,
            hiddenAt: hidden ? Date.now : nil,
        )

        try await saveDeviceToDisk(device)
        cachedDeviceData[device.id] = device

        // Update lists
        try await updateDeviceListsAfterSave(device)

        self.notifyDeviceUpdated(deviceId: device.id, device: device)

        return device.id
    }

    func setDeviceHidden(id: String, hidden: Bool) async throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.hiddenAt = hidden ? Date.now : nil

        try await saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        try await updateDeviceListsAfterSave(device)

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func updateDeviceLocation(id: String, location: String) async throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.location = location

        try await saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func updateDeviceName(id: String, name: String) async throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.name = name

        try await saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func setSelectedApp(deviceId: String, appId: String) throws {
        Log.data.info("App selected \(appId, privacy: .public) for device \(deviceId, privacy: .public)")
    }

    func deleteDevice(id: String) async throws {
        guard let device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        if device.id == self.requestPrimaryDevice()?.id {
            if let newDeviceId = self.requestDeviceList().first {
                try await self.makePrimaryDevice(id: newDeviceId)
            }
        }

        try await deleteDeviceOnDisk(id)
        cachedDeviceData[id] = nil // Remove from cache since it's deleted

        try await updateDeviceListsAfterDelete(udn: id)

        self.notifyDeviceUpdated(deviceId: id, device: nil)
    }

    func setDeviceApps(deviceId: String, apps: [AppLink]) async throws {
        try await saveDeviceAppsToDisk(deviceId: deviceId, apps: apps)
        cachedDeviceApps[deviceId] = apps

        // Update primary apps cache if this is primary device
        if cachedPrimaryDevice?.id == deviceId {
            cachedPrimaryApps = apps
            self.notifyPrimaryAppsUpdated(apps: apps)
        }

        self.notifyDeviceAppsUpdated(deviceId: deviceId, apps: apps)
    }

    func setDeviceDetails(device: Device) async throws {
        try await saveDeviceToDisk(device)
        cachedDeviceData[device.id] = device

        try await updateDeviceListsAfterSave(device)

        // Update primary device cache if this is primary device
        if cachedPrimaryDevice?.id == device.id {
            cachedPrimaryDevice = device
            self.notifyPrimaryDeviceUpdated(device: device)
        }

        self.notifyDeviceUpdated(deviceId: device.id, device: device)
    }

    func saveMessageFromMigration(_ message: Message) async throws {
        try await database.saveMessage(message)
        refreshMessageCache()
    }

    func markMessagesViewed() async throws {
        try await database.markMessagesViewed()
        refreshMessageCache()
    }

#if !WIDGET
    @discardableResult
    func refreshMessages(viewed: Bool) async -> Int {
        let latestMessageId = requestMessages().last { $0.fetchedBackend }?.id

        do {
            let updates = try await getMessagingUpdates(after: latestMessageId)
            if let lastSupportTyping = updates.presence.lastSupportTyping {
                UserDefaults.standard.set(lastSupportTyping.timeIntervalSince1970, forKey: UserDefaultKeys.lastSupportTypingTime)
            }

            var messagesToSave: [Message] = []
            var pendingMessagesToDelete: [String] = []
            for response in updates.messages {
                var message = Message(response)
                if viewed {
                    message.viewed = true
                }
                messagesToSave.append(message)

                if let nonce = message.nonce,
                   let pendingMessage = database.pendingMessage(nonce: nonce) {
                    pendingMessagesToDelete.append(pendingMessage.id)
                }
            }

            if !messagesToSave.isEmpty {
                try await database.saveMessages(messagesToSave)
            }
            for messageId in pendingMessagesToDelete {
                try await database.deleteMessage(id: messageId)
            }
            if !messagesToSave.isEmpty || !pendingMessagesToDelete.isEmpty {
                refreshMessageCache()
            }

            let sentPendingCount = await sendPendingMessagesIfIdle(reason: "refreshMessages")
            return messagesToSave.count + sentPendingCount
        } catch {
            Log.backend.warning("Error refreshing messages: \(error, privacy: .public)")
            await sendPendingMessagesIfIdle(reason: "refreshMessages after refresh failure")
            return 0
        }
    }

    @discardableResult
    func refreshMessagesIfExpectingNewMessages() async -> Int {
        guard UserDefaults.standard.bool(forKey: UserDefaultKeys.hasSentFirstMessage) || hasPendingMessagesToSend() else {
            return 0
        }
        return await refreshMessages(viewed: false)
    }

    func sendChatMessage(message: String, attachment: AttachmentUpload?) async throws {
        let nonce = Self.makeDiscordNonce()
        Log.backend.notice("sendChatMessage started nonce=\(nonce, privacy: .public) contentBytes=\(message.utf8.count, privacy: .public) attachment=\(attachment?.filename ?? "--", privacy: .public)")
        var pendingMessage = Message(
            id: "pending-\(nonce)",
            message: message,
            author: .me,
            fetchedBackend: false,
            viewed: true,
            unsentAttachment: attachment,
            nonce: nonce
        )
        pendingMessage.lastSendAttempt = Date.now

        Log.backend.notice("Saving pending message nonce=\(nonce, privacy: .public) pendingId=\(pendingMessage.id, privacy: .public)")
        try await database.saveMessage(pendingMessage)
        Log.backend.notice("Saved pending message nonce=\(nonce, privacy: .public) pendingId=\(pendingMessage.id, privacy: .public)")
        refreshMessageCache()

        Log.backend.notice("Attempting pending message queue after enqueue nonce=\(nonce, privacy: .public)")
        await sendPendingMessagesIfIdle(reason: "sendChatMessage", force: true)
        Log.backend.notice("sendChatMessage queued nonce=\(nonce, privacy: .public)")
    }

    private func hasPendingMessagesToSend() -> Bool {
        database.messages().contains { message in
            message.author == .me && !message.fetchedBackend && message.nonce != nil
        }
    }

    private func pendingMessagesToSend(force: Bool) -> [Message] {
        let nextAllowedSendAttempt = Date.now.addingTimeInterval(-Self.pendingMessageRetryDelay)
        return database.messages()
            .filter { message in
                guard message.author == .me && !message.fetchedBackend && message.nonce != nil else {
                    return false
                }
                if force {
                    return true
                }
                return message.lastSendAttempt.map { $0 <= nextAllowedSendAttempt } ?? true
            }
            .sorted { lhs, rhs in
                switch (lhs.lastSendAttempt, rhs.lastSendAttempt) {
                case let (left?, right?):
                    if left == right {
                        return lhs.id < rhs.id
                    }
                    return left < right
                case (_?, nil):
                    return false
                case (nil, _?):
                    return true
                case (nil, nil):
                    return lhs.id < rhs.id
                }
            }
    }

    private static func makeDiscordNonce() -> String {
        normalizeDiscordNonce(UUID().uuidString)
    }

    private static func normalizeDiscordNonce(_ nonce: String) -> String {
        if nonce.count <= discordNonceMaxLength {
            return nonce
        }

        let compact = nonce.replacingOccurrences(of: "-", with: "")
        let source = compact.isEmpty ? nonce : compact
        return String(source.prefix(discordNonceMaxLength))
    }

    @discardableResult
    private func sendPendingMessagesIfIdle(reason: String, force: Bool = false) async -> Int {
        guard !isSendingPendingMessages else {
            Log.backend.notice("Skipping pending message send because another send is active reason=\(reason, privacy: .public)")
            return 0
        }

        isSendingPendingMessages = true
        defer {
            isSendingPendingMessages = false
        }

        var sentCount = 0
        while var pendingMessage = pendingMessagesToSend(force: force).first {
            guard var nonce = pendingMessage.nonce else {
                Log.backend.error("Skipping pending message without nonce pendingId=\(pendingMessage.id, privacy: .public)")
                break
            }
            let normalizedNonce = Self.normalizeDiscordNonce(nonce)
            if normalizedNonce != nonce {
                Log.backend.notice("Normalizing pending message nonce pendingId=\(pendingMessage.id, privacy: .public) oldNonce=\(nonce, privacy: .public) newNonce=\(normalizedNonce, privacy: .public)")
                pendingMessage.nonce = normalizedNonce
                nonce = normalizedNonce
            }

            Log.backend.notice("Sending pending message reason=\(reason, privacy: .public) pendingId=\(pendingMessage.id, privacy: .public) nonce=\(nonce, privacy: .public) contentBytes=\(pendingMessage.message.utf8.count, privacy: .public) attachment=\(pendingMessage.unsentAttachment?.filename ?? "--", privacy: .public)")
            pendingMessage.lastSendAttempt = Date.now
            do {
                try await database.saveMessage(pendingMessage)
                refreshMessageCache()
            } catch {
                Log.backend.error("Error updating pending message send attempt pendingId=\(pendingMessage.id, privacy: .public) nonce=\(nonce, privacy: .public): \(error, privacy: .public)")
                return sentCount
            }

            let result = await sendMessageDirect(message: pendingMessage.message, attachment: pendingMessage.unsentAttachment, nonce: nonce)
            switch result {
            case .success(let response):
                Log.backend.notice("Pending message send succeeded pendingId=\(pendingMessage.id, privacy: .public) nonce=\(nonce, privacy: .public) backendMessageId=\(response.id, privacy: .public)")
                var savedMessage = Message(response)
                savedMessage.viewed = pendingMessage.viewed
                do {
                    try await database.saveMessage(savedMessage)
                    try await database.deleteMessage(id: pendingMessage.id)
                    refreshMessageCache()
                    UserDefaults.standard.set(true, forKey: UserDefaultKeys.hasSentFirstMessage)
                    sentCount += 1
                } catch {
                    Log.backend.error("Error saving sent pending message pendingId=\(pendingMessage.id, privacy: .public) nonce=\(nonce, privacy: .public): \(error, privacy: .public)")
                    return sentCount
                }
            case .failure(let error):
                Log.backend.error("Pending message send failed pendingId=\(pendingMessage.id, privacy: .public) nonce=\(nonce, privacy: .public): \(error, privacy: .public)")
                return sentCount
            }
        }

        if sentCount > 0 {
            Log.backend.notice("Finished pending message send reason=\(reason, privacy: .public) sentCount=\(sentCount, privacy: .public)")
        }
        return sentCount
    }
#endif

    func makePrimaryDevice(id: String) async throws {
        guard let device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        // Update device's lastSelectedAt
        var updatedDevice = device
        updatedDevice.lastSelectedAt = Date.now
        try await saveDeviceToDisk(updatedDevice)
        cachedDeviceData[id] = updatedDevice

        try await database.setPrimaryDevice(id: id)

        // Update caches
        cachedPrimaryDevice = updatedDevice
        cachedPrimaryApps = cachedDeviceApps[id] ?? (try? loadDeviceAppsFromDisk(deviceId: id))

        self.notifyPrimaryDeviceUpdated(device: updatedDevice)
        if let apps = self.cachedPrimaryApps {
            self.notifyPrimaryAppsUpdated(apps: apps)
        }
    }

    func reorderDevices(fromOffsets: IndexSet, toOffset: Int) async throws {
        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()
        devices.move(fromOffsets: fromOffsets, toOffset: toOffset)

        try await saveDeviceListToDisk(devices)
        cachedDeviceList = devices

        self.notifyDeviceListUpdated(devices: devices)
    }

    // MARK: - Preload Functions
    func preloadDeviceList() {
        _ = requestDeviceList()
    }

    func preloadHiddenDeviceList() {
        _ = requestHiddenDeviceList()
    }

    func preloadDevice(id: String) {
        _ = requestDevice(id: id)
    }

    func preloadDeviceApps(deviceId: String) {
        _ = requestDeviceApps(deviceId: deviceId)
    }

    func preloadDeviceAppIcon(deviceId: String, appId: String) {
        requestDeviceAppIcon(deviceId: deviceId, appId: appId)
    }

    func preloadPrimaryDevice() {
        _ = requestPrimaryDevice()
    }

    func preloadPrimaryApps() {
        _ = requestPrimaryApps()
    }

    func preloadMessages() {
        _ = requestMessages()
    }

    // MARK: - Private Disk Operations
    private func loadDeviceListFromDisk() throws -> [String] {
        database.deviceList()
    }

    private func loadHiddenDeviceListFromDisk() throws -> [String] {
        database.hiddenDeviceList()
    }

    private func loadDeviceFromDisk(id: String) throws -> Device? {
        database.device(id: id)
    }

    private func loadDeviceAppsFromDisk(deviceId: String) throws -> [AppLink] {
        database.deviceApps(deviceId: deviceId)
    }

    private func loadPrimaryDeviceFromDisk() throws -> Device? {
        database.primaryDevice()
    }

    private func loadPrimaryAppsFromDisk() throws -> [AppLink]? {
        database.primaryApps()
    }

    private func saveDeviceToDisk(_ device: Device) async throws {
        try await database.saveDevice(device)
    }

    private func deleteDeviceOnDisk(_ deviceId: String) async throws {
        try await database.deleteDevice(id: deviceId)
    }

    private func saveDeviceAppsToDisk(deviceId: String, apps: [AppLink]) async throws {
        try await database.saveDeviceApps(deviceId: deviceId, apps: apps)
    }

    private func saveDeviceListToDisk(_ devices: [String]) async throws {
        try await database.saveDeviceList(devices, kind: .visible)
    }

    private func saveHiddenDeviceListToDisk(_ devices: [String]) async throws {
        try await database.saveDeviceList(devices, kind: .hidden)
    }

    // MARK: - Private Helper Methods
    private func updateDeviceListsAfterSave(_ device: Device) async throws {
        let isHidden = device.hiddenAt != nil

        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()
        var hiddenDevices = try cachedHiddenDeviceList ?? loadHiddenDeviceListFromDisk()

        let hasNewPrimary = devices.isEmpty

        let existingVisibleIndex = devices.firstIndex(of: device.id)
        let existingHiddenIndex = hiddenDevices.firstIndex(of: device.id)

        devices.removeAll { $0 == device.id }
        hiddenDevices.removeAll { $0 == device.id }

        // Add to appropriate list
        if isHidden {
            if let existingHiddenIndex {
                hiddenDevices.insert(device.id, at: min(existingHiddenIndex, hiddenDevices.count))
            } else {
                hiddenDevices.append(device.id)
            }
        } else {
            if let existingVisibleIndex {
                devices.insert(device.id, at: min(existingVisibleIndex, devices.count))
            } else {
                devices.insert(device.id, at: 0)
            }
        }

        // Save and update cache
        try await saveDeviceListToDisk(devices)
        try await saveHiddenDeviceListToDisk(hiddenDevices)

        cachedDeviceList = devices
        cachedHiddenDeviceList = hiddenDevices

        if hasNewPrimary {
            try await self.makePrimaryDevice(id: device.id)
        }

        self.notifyDeviceListUpdated(devices: devices)
        self.notifyHiddenDeviceListUpdated(devices: hiddenDevices)
    }

    private func updateDeviceListsAfterDelete(udn: String) async throws {
        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()
        var hiddenDevices = try cachedHiddenDeviceList ?? loadHiddenDeviceListFromDisk()

        devices.removeAll { $0 == udn }
        hiddenDevices.removeAll { $0 == udn }

        try await saveDeviceListToDisk(devices)
        try await saveHiddenDeviceListToDisk(hiddenDevices)

        cachedDeviceList = devices
        cachedHiddenDeviceList = hiddenDevices

        self.notifyDeviceListUpdated(devices: devices)
        self.notifyHiddenDeviceListUpdated(devices: hiddenDevices)
    }

    private func refreshMessageCache() {
        let messages = database.messages()
        let unreadCount = database.unreadMessageCount()
        cachedMessages = messages
        cachedUnreadMessageCount = unreadCount
        notifyMessagesUpdated(messages: messages, unreadCount: unreadCount)
    }

    private func handleExternalDatabaseChange() {
        Log.data.notice("Reloading in-memory data after external database change")

        let oldDeviceIDs = Set(cachedDeviceData.keys)
        let oldAppDeviceIDs = Set(cachedDeviceApps.keys)

        let visibleIDs = database.deviceList()
        let hiddenIDs = database.hiddenDeviceList()
        let allDeviceIDs = Set(visibleIDs + hiddenIDs)

        cachedDeviceList = visibleIDs
        cachedHiddenDeviceList = hiddenIDs
        cachedDeviceData = [:]
        cachedDeviceApps = [:]

        for deviceID in allDeviceIDs {
            if let device = database.device(id: deviceID) {
                cachedDeviceData[deviceID] = device
            }
            cachedDeviceApps[deviceID] = database.deviceApps(deviceId: deviceID)
        }

        cachedPrimaryDevice = database.primaryDevice()
        cachedPrimaryApps = database.primaryApps()
        let messages = database.messages()
        let unreadCount = database.unreadMessageCount()
        cachedMessages = messages
        cachedUnreadMessageCount = unreadCount

        notifyDeviceListUpdated(devices: visibleIDs)
        notifyHiddenDeviceListUpdated(devices: hiddenIDs)
        notifyPrimaryDeviceUpdated(device: cachedPrimaryDevice)
        notifyPrimaryAppsUpdated(apps: cachedPrimaryApps)
        notifyMessagesUpdated(messages: messages, unreadCount: unreadCount)

        for deviceID in oldDeviceIDs.union(allDeviceIDs) {
            notifyDeviceUpdated(deviceId: deviceID, device: cachedDeviceData[deviceID])
        }

        for deviceID in oldAppDeviceIDs.union(allDeviceIDs) {
            notifyDeviceAppsUpdated(deviceId: deviceID, apps: cachedDeviceApps[deviceID] ?? [])
        }
    }
}

// MARK: - Registration System Implementation
extension RoamDataHandler {
    nonisolated func token() -> RegistrationToken {
        return UUID()
    }

    func register(_ token: RegistrationToken, _ listener: RegistrationListener) {
        self.updateListeners[token] = RegistrationListenerRef(listener: listener)
    }

    func unregister(_ token: RegistrationToken) {
        self.updateListeners.removeValue(forKey: token)

        for change in self.updateRegistrations.keys {
            if var listeners = self.updateRegistrations[change] {
                if listeners.remove(token) != nil {
                    self.updateRegistrations[change] = listeners
                }
            }
            if self.updateRegistrations[change]?.isEmpty ?? true {
                self.updateRegistrations.removeValue(forKey: change)
            }
        }
    }

    func registerForChange(_ token: RegistrationToken, change: ChangeOperation) {
        var listeners = self.updateRegistrations[change] ?? []
        listeners.insert(token)
        self.updateRegistrations[change] = listeners
    }

    // MARK: - Notification Methods
    private func notifyDeviceListUpdated(devices: [String]) {
        let change = ChangeOperation.updateDeviceList
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.deviceListUpdated(devices: devices)
            }
        }
    }

    private func notifyHiddenDeviceListUpdated(devices: [String]) {
        let change = ChangeOperation.updateHiddenDeviceList
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.hiddenDeviceListUpdated(devices: devices)
            }
        }
    }

    private func notifyDeviceUpdated(deviceId: String, device: Device?) {
        let change = ChangeOperation.updateDevice(deviceId: deviceId)
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.deviceDetailUpdated(for: deviceId, device: device)
            }
        }
    }

    private func notifyDeviceAppsUpdated(deviceId: String, apps: [AppLink]) {
        let change = ChangeOperation.updateDeviceApps(deviceId: deviceId)
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.deviceAppsUpdated(for: deviceId, apps: apps)
            }
        }
    }

    private func notifyAppIconUpdated(deviceId: String, appId: String, iconDataHash: String) {
        let change = ChangeOperation.updateAppIcon(deviceId: deviceId, appId: appId)
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.appIconUpdated(for: deviceId, appId: appId, iconDataHash: iconDataHash)
            }
        }
    }

    private func notifyPrimaryDeviceUpdated(device: Device?) {
        let change = ChangeOperation.updatePrimaryDevice
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.primaryDeviceUpdated(device: device)
            }
        }
    }

    private func notifyPrimaryAppsUpdated(apps: [AppLink]?) {
        let change = ChangeOperation.updatePrimaryApps
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.primaryAppsUpdated(apps: apps)
            }
        }
    }

    private func notifyMessagesUpdated(messages: [Message], unreadCount: Int) {
        let change = ChangeOperation.updateMessages
        self.updateRegistrations[change]?.forEach { token in
            guard let listener = self.updateListeners[token]?.listener else {
                self.unregister(token)
                return
            }

            DispatchQueue.main.async {
                listener.messagesUpdated(messages: messages, unreadCount: unreadCount)
            }
        }
    }

    // MARK: - Device Management Extension
#if !WIDGET
    func requestDeviceForSerial(serial: String) async -> Device? {
        // First check all cached devices for matching serial
        for cachedDevice in cachedDeviceData.values where cachedDevice.serial == serial {
            return cachedDevice
        }

        if let device = database.device(serial: serial) {
            cachedDeviceData[device.id] = device
            return device
        }

        return nil
    }

    @discardableResult
    func addOrReplaceDevice(location: String, id: String? = nil, serial: String? = nil) async throws -> String {
        // Check if device exists by UDN
        if let id, let device = self.requestDevice(id: id) {
            var updatedDevice = device
            updatedDevice.location = location
            do {
                try await self.setDeviceDetails(device: updatedDevice)
                return updatedDevice.id
            } catch {
                Log.data.warning("Error updating device fields: \(error, privacy: .public)")
                throw error
            }
        }

        // Check if device exists by serial
        if let serial, let device = await self.requestDeviceForSerial(serial: serial) {
            var updatedDevice = device
            updatedDevice.location = location
            do {
                try await self.setDeviceDetails(device: updatedDevice)
                return updatedDevice.id
            } catch {
                Log.data.warning("Error updating device fields: \(error, privacy: .public)")
                throw error
            }
        }

        // Fetch preconnection info to get device details
        let info: PreconnectionDeviceInfo
        var foundDevice: Device?
        do {
            info = try await fetchPreconnectionInfo(location: location)

            // Check again with the UDN from preconnection info
            if let device = requestDevice(id: info.udn) {
                Log.data.info("Found device for udn \(info.udn, privacy: .public), updating")
                var updatedDevice = device
                updatedDevice.serial = info.serial
                updatedDevice.location = location
                foundDevice = updatedDevice
            } else if let device = await requestDeviceForSerial(serial: info.serial) {
                Log.data.info("Found device for serial \(info.serial, privacy: .public), updating")
                var updatedDevice = device
                updatedDevice.udn = info.udn
                updatedDevice.location = location
                foundDevice = updatedDevice
            }
        } catch {
            Log.data.warning("Trying to add device but no preconnection info available \(location, privacy: .public). Error: \(error, privacy: .public)")
            throw error
        }

        let device: Device

        if let foundDevice = foundDevice {
            device = foundDevice
        } else {
            Log.data.notice("Adding device at \(location, privacy: .public)")
            device = Device(
                name: info.friendlyName,
                location: location,
                udn: info.udn,
                serial: info.serial
            )
        }

        do {
            try await self.setDeviceDetails(device: device)
            Log.data.notice("Added device \(device.id, privacy: .public)")

            // Trigger device refresh in background
            Task {
                #if os(watchOS)
                let refreshClient = WatchOSRefreshClient(id: device.id, location: location)
                #else
                let ecpClient: ECPWebsocketClient
                do {
                    guard let locationURL = URL(string: location) else {
                        throw APIError.badURLError(location)
                    }
                    ecpClient = ECPWebsocketClient(location: locationURL)
                    await ecpClient.start()
                } catch {
                    Log.data.warning("Error refreshing device b/c no ECP Session: \(error, privacy: .public)")
                    return
                }
                defer {
                    Task {
                        await ecpClient.cancel()
                    }
                }
                let refreshClient = ECPWebsocketRefreshClient(id: device.id, client: ecpClient, location: device.location)
                #endif
                await self.refreshDevice(client: refreshClient)
            }

            return device.id
        } catch {
            Log.data.warning("Error adding device at \(location, privacy: .public), \(error, privacy: .public)")
            throw error
        }
    }

    func sentToWatch(deviceId: String) async {
        do {
            if var device = self.requestDevice(id: deviceId) {
                device.lastSentToWatch = Date.now
                try await self.setDeviceDetails(device: device)
            }
        } catch {
            Log.data.warning("Error marking device \(deviceId, privacy: .public) as sent to watch: \(error, privacy: .public)")
        }
    }

    func resetWatchData() async {
        do {
            let allDeviceIds = self.requestDeviceList()

            for deviceId in allDeviceIds {
                if var device = self.requestDevice(id: deviceId) {
                    device.lastSentToWatch = nil
                    try await self.setDeviceDetails(device: device)
                }
            }
        } catch {
            Log.data.warning("Error marking devices as not sent to watch: \(error, privacy: .public)")
        }
    }
#endif
}

// MARK: - Refreshing
protocol RefreshClient: Sendable {
    func getId() async throws -> String
    func getDeviceInfo() async throws -> DeviceInfo
    func getDeviceCapabilities() async throws -> DeviceCapabilities
    func getDeviceApps() async throws -> [ AppLink]
    func getDeviceAppIcon(_ appId: String) async throws -> Data
    func getDeviceIcon() async throws -> Data
}

#if !WIDGET
extension RoamDataHandler {
    private static let minRescanInterval: TimeInterval = 30

    func refreshDevice(client: any RefreshClient) async {
        let deviceId: String
        do {
            deviceId = try await client.getId()
            Log.data.notice("Refreshing device with id \(deviceId, privacy: .public)")
        } catch {
            Log.data.error("Failed to refresh device because couldn't get id: \(error, privacy: .public)")
            return
        }

        // Check if device was recently refreshed
        let existingDevice = self.requestDevice(id: deviceId)
        let lastRefreshed = existingDevice?.lastSyncAt ?? .distantPast

        if lastRefreshed.advanced(by: RoamDataHandler.minRescanInterval) > .now {
            Log.data.notice("Device refresh skipped for id \(deviceId, privacy: .public) b/c last refreshed \(lastRefreshed, privacy: .public)")
            return
        } else {
            Log.data.notice("Refreshing device with id \(deviceId, privacy: .public) lastRefreshed \(lastRefreshed, privacy: .public)")
        }

        // Get device info from client
        let deviceInfo: DeviceInfo
        do {
            deviceInfo = try await client.getDeviceInfo()
            Log.data.notice("Successfully refreshed device info")
        } catch {
            Log.data.error("Failed to get device info \(deviceId, privacy: .public), \(error, privacy: .public)")
            return
        }

        // Update or create device with basic info
        var device: Device
        if let existingDevice = existingDevice {
            if deviceInfo.udn != existingDevice.udn {
                Log.data.warning("Error: trying to refresh device with udn \(deviceInfo.udn, privacy: .public), but device already has udn \(existingDevice.udn, privacy: .public)")
                return
            }
            device = existingDevice
        } else {
            // Create new device
            device = Device(
                name: deviceInfo.friendlyDeviceName ?? getGlobalNewDeviceName(),
                location: "", // Will be set by caller
                udn: deviceInfo.udn,
                serial: nil
            )
        }

        // Update device timestamps and basic info
        device.lastOnlineAt = Date.now
        device.lastSyncAt = Date.now
        device.ethernetMAC = deviceInfo.ethernetMac
        device.wifiMAC = deviceInfo.wifiMac
        device.networkType = deviceInfo.networkType
        device.powerMode = deviceInfo.powerMode

        // Update device name if it's still the default
        if device.name == getGlobalNewDeviceName(), let newName = deviceInfo.friendlyDeviceName {
            device.name = newName
        }

        // Check if we need to do full scan
        let existingApps = self.requestDeviceApps(deviceId: deviceId)
        let shouldSkipFullScan = (device.lastScannedAt?.timeIntervalSinceNow ?? -10000.0) > -RoamDataHandler.minRescanInterval &&
        existingApps.allSatisfy({ $0.iconHash != nil }) &&
        existingApps.count > 0

        do {
            try await self.setDeviceDetails(device: device)
        } catch {
            Log.data.error("Failed to save device details: \(error, privacy: .public)")
        }

        if shouldSkipFullScan {
            Log.data.notice("Returning early from refresh - recent scan with all icons")
            return
        }

        device.lastScannedAt = Date.now

        Log.data.notice("Refreshing capabilities and apps")

        // Get device capabilities
        var capabilities: DeviceCapabilities?
        do {
            capabilities = try await client.getDeviceCapabilities()
            Log.data.notice("Successfully refreshed capabilities")
        } catch {
            Log.data.error("Error getting capabilities: \(error, privacy: .public)")
        }

        // Get device apps
        var fetchedApps: [AppLink]?
        do {
            fetchedApps = try await client.getDeviceApps()
            fetchedApps = fetchedApps?.map { app in
                var app = app
                app.deviceId = deviceId
                return app
            }
            Log.data.notice("Successfully refreshed device apps")
        } catch {
            Log.data.error("Error getting device apps: \(error, privacy: .public)")
        }

        // Update device with capabilities
        if let capabilities = capabilities {
            device.rtcpPort = capabilities.rtcpPort
            device.supportsDatagram = capabilities.supportsDatagram
        }

        // Process apps if we got them
        var appsNeedingIcons: [String] = []
        var earlyUpdatedApps: [AppLink]?
        var afterUpdateApps = existingApps

        if let fetchedApps = fetchedApps {
            var shouldUpdate: Bool = false

            if fetchedApps.count != existingApps.count {
                shouldUpdate = true
            } else {
                for i in 0..<fetchedApps.count {
                    let fa = fetchedApps[i]
                    let ca = existingApps[i]

                    if fa.id != ca.id || fa.name != ca.name || fa.type != ca.type {
                        shouldUpdate = true
                        break
                    }
                }
            }

            if shouldUpdate {
                earlyUpdatedApps = fetchedApps.map{ fa in
                    var fa = fa
                    fa.iconHash = existingApps.first(where: { $0.id == fa.id })?.iconHash
                    return fa
                }
                afterUpdateApps = earlyUpdatedApps ?? []
            }

            // Find apps that need icons
            for app in afterUpdateApps where (app.iconHash == nil || (app.lastSyncAt ?? .distantPast).advanced(by: 3600 * 24) < .now) {
                appsNeedingIcons.append(app.id)
            }
        }

        // Save updated device and apps
        do {
            try await self.setDeviceDetails(device: device)
            if let earlyUpdatedApps {
                try await self.setDeviceApps(deviceId: deviceId, apps: earlyUpdatedApps)
            }
        } catch {
            Log.data.error("Failed to save device and apps: \(error, privacy: .public)")
        }

        // Get device icon if needed
        var deviceIcon: Data?
        let deviceNeedsIcon = device.iconHash == nil
        if deviceNeedsIcon {
            Log.data.notice("Getting icon for device")
            do {
                deviceIcon = try await client.getDeviceIcon()
            } catch {
                Log.data.warning("Error getting device icon: \(error, privacy: .public)")
            }
        }

        // Get app icons
        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                Log.data.notice("Getting device app icon for id \(appId, privacy: .public)")
                let iconData = try await client.getDeviceAppIcon(appId)
                Log.data.notice("Successfully refreshed device app icon")
                appIcons[appId] = iconData
            } catch {
                Log.data.error("Error getting device app icon: \(error, privacy: .public)")
            }
        }

        // Store icons and update hashes
        if let deviceIconData = deviceIcon {
            let iconHash = fastHashData(data: deviceIconData)
            do {
                try storeIconToDisk(iconData: deviceIconData, hash: iconHash)
                device.iconHash = iconHash
                try await self.setDeviceDetails(device: device)
                Log.data.notice("Stored device icon")
            } catch {
                Log.data.error("Error storing device icon: \(error, privacy: .public)")
            }
        }

        // Store app icons and update app records
        if !appIcons.isEmpty {
            var appsToUpdate: [AppLink] = []

            for (appId, iconData) in appIcons {
                let iconHash = fastHashData(data: iconData)
                do {
                    try storeIconToDisk(iconData: iconData, hash: iconHash)

                    // Find and update the app with the new icon hash
                    if let appIndex = afterUpdateApps.firstIndex(where: { $0.id == appId }) {
                        afterUpdateApps[appIndex].iconHash = iconHash
                        afterUpdateApps[appIndex].lastSyncAt = .now
                        appsToUpdate.append(afterUpdateApps[appIndex])
                    }

                    notifyAppIconUpdated(deviceId: deviceId, appId: appId, iconDataHash: iconHash)

                    Log.data.notice("Stored app icon for \(appId)")
                } catch {
                    Log.data.error("Error storing app icon for \(appId): \(error, privacy: .public)")
                }
            }

            // Save updated apps with icon hashes
            if !appsToUpdate.isEmpty {
                do {
                    try await self.setDeviceApps(deviceId: deviceId, apps: afterUpdateApps)
                } catch {
                    Log.data.error("Failed to save apps with updated icons: \(error, privacy: .public)")
                }
            }
        }

        Log.data.notice("Device refresh completed for \(deviceId)")
    }
}
#endif

#if os(watchOS) && !WIDGET
actor WatchOSRefreshClient: RefreshClient {
    let id: String
    let location: String

    init(id: String, location: String) {
        self.id = id
        self.location = location
    }

    func getId() throws -> String {
        return self.id
    }

    func getDeviceInfo() async throws -> DeviceInfo {
        return try await fetchDeviceInfo(location: location)
    }

    func getDeviceCapabilities() async throws -> DeviceCapabilities {
        return try await fetchDeviceCapabilities(location: location)
    }

    func getDeviceApps() async throws -> [ AppLink] {
        return try await fetchDeviceApps(location: location)
    }

    func getDeviceAppIcon(_ appId: String) async throws -> Data {
        return try await fetchAppIcon(location: location, appId: appId)
    }

    func getDeviceIcon() async throws -> Data {
        let info = try await fetchPreconnectionInfo(location: location)
        return try await fetchDeviceIcon(info: info)
    }
}
#elseif !WIDGET
actor ECPWebsocketRefreshClient: RefreshClient {
    let id: String
    let client: ECPWebsocketClient
    let location: String

    init(id: String, client: ECPWebsocketClient, location: String) {
        self.id = id
        self.client = client
        self.location = location
    }

    func getId() throws -> String {
        return self.id
    }

    func getDeviceInfo() async throws -> DeviceInfo {
        return try await client.getDeviceInfo()
    }

    func getDeviceCapabilities() async throws -> DeviceCapabilities {
        return try await client.getDeviceCapabilities()
    }

    func getDeviceApps() async throws -> [ AppLink] {
        return try await client.getDeviceApps()
    }

    func getDeviceAppIcon(_ appId: String) async throws -> Data {
        return try await client.getDeviceAppIcon(appId)
    }

    func getDeviceIcon() async throws -> Data {
        let info = try await fetchPreconnectionInfo(location: location)
        return try await fetchDeviceIcon(info: info)
    }
}
#endif

// MARK: - Constants
public let legacyContainerAppGroup = "group.com.msdrigg.roam.models"
public let mainAppGroup = "group.com.msdrigg.roam"

// MARK: - Testing Support
extension RoamDataHandler {
    func initialize() async {
        if loadTestingData() {
            // swiftlint:disable:next force_try
            try! await self.loadTestData()
        } else if usingTestingData() {
            // swiftlint:disable:next force_try
            try! await self.clearData()
        }
    }

    private func loadTestData() async throws {
        // Clear existing data first
        try await clearData()

        #if DEBUG
        // Load test devices
        let testDevices = getTestingDevices()
        var deviceIds: [String] = []

        for device in testDevices {
            try await saveDeviceToDisk(device)
            cachedDeviceData[device.id] = device
            deviceIds.append(device.id)

            // Load apps for this device
            let testApps = getTestingAppLinks(deviceId: device.udn)
            try await saveDeviceAppsToDisk(deviceId: device.id, apps: testApps)
            cachedDeviceApps[device.id] = testApps
        }

        // Save device lists
        try await saveDeviceListToDisk(deviceIds)
        cachedDeviceList = deviceIds

        // Initialize empty hidden device list
        cachedHiddenDeviceList = []
        try await saveHiddenDeviceListToDisk([])

        // Set first device as primary if available
        if let firstDevice = testDevices.first {
            try await self.makePrimaryDevice(id: firstDevice.id)
        }

        // Load test messages
        let testMessages = getTestingMessages()
        for message in testMessages {
            try await database.saveMessage(message)
        }

        Log.data.info("Loaded test data: \(testDevices.count) devices, \(testDevices.map { cachedDeviceApps[$0.id]?.count ?? 0 }.reduce(0, +)) total apps, \(testMessages.count) messages")
        #endif
    }

    private func clearData() async throws {
        // Clear all caches
        cachedDeviceData.removeAll()
        cachedDeviceApps.removeAll()
        cachedDeviceList = nil
        cachedHiddenDeviceList = nil
        cachedPrimaryDevice = nil
        cachedPrimaryApps = nil

        try await database.clearAll()

        Log.data.info("Cleared all data and caches")
    }
}

public func inScreenshotTestingContext() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-ScreenshotTesting")
    #else
    return false
    #endif
}

private func usingTestingData() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-DataTesting")
    #else
    return false
    #endif
}

private func loadTestingData() -> Bool {
    #if DEBUG
    return CommandLine.arguments.contains("-DataLoadTestingData")
    #else
    return false
    #endif
}
