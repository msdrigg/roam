import Foundation
import OSLog
import SwiftData
import SwiftUI

func getGlobalNewDeviceName() -> String {
    return String(localized: "New device")
}

@ModelActor
actor RoamDataHandler {
    static let hardDeleteTimeout: TimeInterval = 3600

    private let minRescanInterval: TimeInterval = 30

    @MainActor
    init() {
        self.init(modelContainer: getSharedModelContainer())
    }

    @MainActor
    static func checkedCreate() throws (ModelContainerFailureReason) -> Self {
        return try self.init(modelContainer: getSharedModelContainerChecked())
    }

    private func allDevices() async throws -> [Device] {
        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            },
            sortBy: [
                SortDescriptor(\Device.lastSelectedAt, order: .reverse),
                SortDescriptor(\Device.lastOnlineAt, order: .reverse),
            ]
        )
        let links = try await self.fetchSafer(
            descriptor
        )
        return links
    }

    func setSelectedDevice(_ id: PersistentIdentifier) async throws {
        Log.data.notice("Updating selectedAt for device with id \(String(describing: id), privacy: .public)")
        if let device = await self.existingDevice(for: id) {
            Log.data.notice("Found device to update with location \(device.location, privacy: .public)")
            device.lastSelectedAt = Date.now
            do {
                try await self.saveSafer()
            } catch {
                Log.data.error("Error marking device as selected \(device.location, privacy: .public)")
                throw error
            }
        }
    }

    func updateDevice(_ id: PersistentIdentifier, name: String? = nil, location: String? = nil, hidden: Bool? = nil) async throws {
        Log.data.notice("Updating device at \(id.described(), privacy: .public)")
        if let device = await self.existingDevice(for: id) {
            Log.data.notice("Found device to update with id \(id.described(), privacy: .public))")
            if let location {
                device.location = location
            }
            if let name {
                device.name = name
            }
            device.lastSentToWatch = nil
            if let hidden {
                if hidden {
                    device.hiddenAt = device.hiddenAt ?? Date.now
                } else {
                    device.hiddenAt = nil
                }
            }
            do {
                try await self.saveSafer()
            } catch {
                Log.data.warning("Error updating device at location \(device.location, privacy: .public)")
                throw error
            }
        } else {
            throw DataHandlerError.deviceNotFound
        }
        Log.data.notice("Updated device at \(id.described(), privacy: .public)")
    }

    @discardableResult
    func addDeviceIndistriminantly(location: String, friendlyDeviceName: String, udn: String, serial: String, hidden: Bool) async throws -> PersistentIdentifier {
        if let device = await deviceForUdn(udn: udn) {
            device.location = location
            device.name = friendlyDeviceName
            device.hiddenAt = hidden ? Date.now : nil
            do {
                try await self.saveSafer()
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
                throw error
            }
            return device.persistentModelID
        } else {
            Log.data.notice("Adding device at \(location, privacy: .public)")
            let device = Device(
                name: friendlyDeviceName,
                location: location,
                udn: udn,
                serial: serial,
            )
            device.hiddenAt = hidden ? Date.now : nil
            modelContext.insert(device)

            do {
                try await self.saveSafer()
                Log.data.notice("Added device \(String(describing: device.persistentModelID), privacy: .public)")
                return device.persistentModelID
            } catch {
                Log.data.warning("Error adding device at \(location, privacy: .public), \(error, privacy: .public)")
                throw error
            }
        }
    }

#if !WIDGET
    @discardableResult
    func addOrReplaceDevice(location: String, udn: String? = nil, serial: String? = nil) async throws -> PersistentIdentifier {
        if let udn, let device = await deviceForUdn(udn: udn) {
            device.location = location
            do {
                try await self.saveSafer()
                return device.persistentModelID
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
                throw error
            }
        }

        if let serial, let device = await deviceForSerial(serial: serial) {
            device.location = location
            do {
                try await self.saveSafer()
                return device.persistentModelID
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
                throw error
            }
        }

        let info: PreconnectionDeviceInfo
        var foundDevice: Device?
        do {
            info = try await fetchPreconnectionInfo(location: location)
            if let device = await deviceForUdn(udn: info.udn) {
                Log.data.info("Found device for udn \(info.udn, privacy: .public), updating")
                device.serial = info.serial
                device.location = location
                foundDevice = device
            } else if let device = await deviceForSerial(serial: info.serial) {
                Log.data.info("Found device for serial \(info.serial, privacy: .public), updating")
                device.udn = info.udn
                device.location = location
                foundDevice = device
            }
        } catch {
            Log.data.warning("Trying to add device but no preconnection info available \(location, privacy: .public). Error: \(error, privacy: .public)")
            throw error
        }

        let device: Device

        if let foundDevice {
            device = foundDevice
        } else {
            Log.data.notice("Adding device at \(location, privacy: .public)")
            let addedDevice = Device(
                name: info.friendlyName,
                location: location,
                udn: info.udn,
                serial: info.serial
            )
            modelContext.insert(addedDevice)
            device = addedDevice
        }

        do {
            try await self.saveSafer()
            Log.data.notice("Added device \(String(describing: device.persistentModelID), privacy: .public)")
            Task {
                #if os(watchOS)
                let refreshClient = WatchOSRefreshClient(id: device.persistentModelID, location: location)
                #else
                let ecpClient: ECPWebsocketClient
                do {
                    guard let location = URL(string: location) else {
                        throw APIError.badURLError(location)
                    }
                    ecpClient = ECPWebsocketClient(location: location)
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
                let refreshClient = ECPWebsocketRefreshClient(id: device.persistentModelID, client: ecpClient, location: device.location)
                #endif
                await self.refreshDevice(client: refreshClient)
            }

            return device.persistentModelID
        } catch {
            Log.data.warning("Error adding device at \(location, privacy: .public), \(error, privacy: .public)")
            throw error
        }
    }

    func sentToWatch(deviceId: PersistentIdentifier) async {
        do {
            if let device = await self.existingDevice(for: deviceId) {
                device.lastSentToWatch = Date.now
                try await self.saveSafer()
            }
        } catch {
            Log.data.warning("Error marking device \(deviceId.described(), privacy: .public) as sent to watch \(error, privacy: .public)")
        }
    }

    func watchPossiblyDead() async {
        let devices = (try? await allDevices()) ?? []
        for device in devices {
            device.lastSentToWatch = nil
        }
        do {
            try await self.saveSafer()
        } catch {
            Log.data.warning("Error marking devices as not sent to watch \(error, privacy: .public)")
        }
    }

    func deleteInPast() async {
        Log.data.notice("Hard deleting devices")
        let deleteBefore = Date.now - Self.hardDeleteTimeout
        let distantFuture = Date.distantFuture
        do {
            let descriptor = FetchDescriptor<Device>(predicate: #Predicate {
                $0.deletedAt ?? distantFuture < deleteBefore
            })
            let models = try await self.fetchSafer(descriptor)

            for model in models {
                Log.data.notice("Deleteing device and apps \(model.location, privacy: .public) with name \(model.name, privacy: .public)")
                do {
                    try deleteAppsForDeviceUdn(udn: model.udn)
                } catch {
                    Log.data.warning("Error deleting past apps for device \(model.udn, privacy: .public) \(error, privacy: .public)")
                }
                modelContext.delete(model)
            }

            let appFetchDescriptor = FetchDescriptor<AppLink>(predicate: #Predicate {
                $0.deletedAt ?? distantFuture < deleteBefore
            })
            let appModels = try await self.fetchSafer(appFetchDescriptor)

            for model in appModels {
                Log.data.notice("Deleteing app \(model.id, privacy: .public) for device \(model.deviceUid ?? "--", privacy: .public) with name \(model.name, privacy: .public)")
                modelContext.delete(model)
            }

            try await self.saveSafer()
        } catch {
            Log.data.warning("Error deleting past devices \(error, privacy: .public)")
        }
    }

//    func hide(_ id: PersistentIdentifier) async throws (DataHandlerError) {
    func hide(_ id: PersistentIdentifier) async throws {
        Log.data.notice("Hiding device \(String(describing: id), privacy: .public)")
        if let device = await self.existingDevice(for: id) {
            device.hiddenAt = .now
            do {
                try await self.saveSafer()
            } catch {
                Log.data.error("Error hiding device with id \(id.described(), privacy: .public)")
                throw error
            }
        }
    }

//    func delete(_ id: PersistentIdentifier) async throws (DataHandlerError) {
    func delete(_ id: PersistentIdentifier) async throws {
        Log.data.notice("Soft deleting device \(String(describing: id), privacy: .public)")
        if let device = await self.existingDevice(for: id) {
            device.deletedAt = .now
            do {
                try await self.saveSafer()
            } catch {
                Log.data.error("Error deleting device with id \(id.described(), privacy: .public)")
                throw error
            }
        }

        await deleteInPast()
    }
#endif

    private func deviceForUdn(udn: String) async -> Device? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.udn == udn
            }
        )
        matchingIds.fetchLimit = 1
        do {
            let matchingIds = try modelContext.fetchIdentifiers(matchingIds)

            if let matchingPid = matchingIds.first {
                if let device = await self.existingDevice(for: matchingPid) {
                    return device
                }
            }
        } catch {
            Log.data.error("Error checking if device exists \(udn, privacy: .public): \(error, privacy: .public)")
        }
        return nil
    }

    private func deviceForSerial(serial: String) async -> Device? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.serial == serial
            }
        )
        matchingIds.fetchLimit = 1
        do {
            let matchingIds = try modelContext.fetchIdentifiers(matchingIds)

            if let matchingPid = matchingIds.first {
                if let device = await self.existingDevice(for: matchingPid) {
                    return device
                }
            }
        } catch {
            Log.data.error("Error checking if device exists \(serial, privacy: .public): \(error, privacy: .public)")
        }
        return nil
    }

    func deviceEntityForUdn(udn: String) async -> DeviceAppEntity? {
        return await deviceForUdn(udn: udn)?.toAppEntity()
    }

    func deviceExists(id: String) async -> Bool {
        await deviceForUdn(udn: id) != nil
    }

    func fetchSelectedDeviceAppEntity() async -> DeviceAppEntity? {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]
        descriptor.fetchLimit = 1

        let selectedDevice: Device? = try? await self.fetchSafer(descriptor).first

        return selectedDevice?.toAppEntity()
    }
}

extension RoamDataHandler {
    public func deviceEntities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
        let descriptor = FetchDescriptor<Device>(predicate: #Predicate {
            identifiers.contains($0.udn) && $0.deletedAt == nil
        })

        let links = try await self.fetchSafer(descriptor)

        return links.map { $0.toAppEntity() }
    }

    public func deviceEntities(matching string: String) async throws -> [DeviceAppEntity] {
        let descriptor = FetchDescriptor<Device>(predicate: #Predicate {
            $0.name.contains(string) && $0.deletedAt == nil
        })

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func allDeviceEntitiesIncludingDeleted() async throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { _ in
                true
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]

        let links = try await self.fetchSafer(
            descriptor
        )
        return links.map { $0.toAppEntity() }
    }

    public func allDeviceEntities() async throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]

        let links = try await self.fetchSafer(
            descriptor
        )
        return links.map { $0.toAppEntity() }
    }

    public func loadLoadTestData() async throws {
        #if DEBUG
        try self.clearData()

        let (devices, apps) = getLoadTestingData()
        for device in devices {
            modelContext.insert(device)
        }
        for app in apps {
            modelContext.insert(app)
        }

        for message in getTestingMessages() {
            message.viewed = true

            modelContext.insert(message)
        }

        try await self.saveSafer()
        #endif
    }

    public func loadTestData() async throws {
        #if DEBUG
        try self.clearData()

        for device in getTestingDevices() {
            modelContext.insert(device)
            for app in getTestingAppLinks(deviceUid: device.udn) {
                modelContext.insert(app)
            }
        }

        for message in getTestingMessages() {
            message.viewed = true

            modelContext.insert(message)
        }

        try await self.saveSafer()
        #endif
    }

    public func clearData() throws {
        try modelContext.delete(model: Device.self)
        try modelContext.delete(model: AppLink.self)
        try modelContext.delete(model: Message.self)
    }
}

enum DataHandlerError: Error, LocalizedError {
    case suspending
    case noSpaceOnDisk
    case noContainerURL
    case deviceNotFound
    case rootError(LocalizedError)
    case unknown

    var errorDescription: String {
        switch self {
        case .noContainerURL:
            return String(localized: "No valid container found")
        case .noSpaceOnDisk:
            return String(localized: "No disk storage left")
        case .suspending:
            return String(localized: "App currently shutting down.")
        case .deviceNotFound:
            return String(localized: "Cannot update device that is deleted.")
        case .unknown:
            return String(localized: "Operation failed.")
        case .rootError(let error):
            return error.errorDescription ?? String(localized: "Operation failed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noContainerURL:
            return String(localized: "This is a bug. Please reach out to roam-support@msd3.io for help")
        case .noSpaceOnDisk:
            return String(localized: "Please delete some files to clear up some space and try again")
        case .suspending:
            return String(localized: "Please re-open the app and try again.")
        case .deviceNotFound:
            return String(localized: "Please make sure the device you are updating has been added.")
        case .unknown:
            return String(localized: "Please close and re-open the app and then try again.")
        case .rootError(let error):
            return error.recoverySuggestion ?? String(localized: "Please close and re-open the app and then try again.")
        }
    }

    static func from(error: Error) -> Self {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            return .noSpaceOnDisk
        }
        if let error = error as? LocalizedError {
            return .rootError(error)
        }
        return .unknown
    }
}

extension RoamDataHandler {
    #if !os(macOS)
    func fetchSafer<T>(_ descriptor: FetchDescriptor<T>) async throws -> [T] {
        let assertion = await QRunInBackgroundAssertion(name: "FetchSafer")
        do {
            if await !assertion.isReleased() {
                let res = try self.modelContext.fetch(descriptor)
                await assertion.release()
                return res
            }
            await assertion.release()
        } catch {
            await assertion.release()
            throw DataHandlerError.from(error: error)
        }
        throw DataHandlerError.suspending
    }
    #else
    func fetchSafer<T>(_ descriptor: FetchDescriptor<T>) async throws -> [T] {
        do {
            return try self.modelContext.fetch(descriptor)
        } catch {
            throw DataHandlerError.from(error: error)
        }
    }
    #endif

    #if !os(macOS)
    func saveSafer() async throws {
        let assertion = await QRunInBackgroundAssertion(name: "SaveSafer")
        do {
            if await !assertion.isReleased() {
                try self.modelContext.save()
            } else {
                throw DataHandlerError.suspending
            }
        } catch {
            await assertion.release()
            throw DataHandlerError.from(error: error)
        }
        await assertion.release()
    }
    #else
    func saveSafer() async throws (DataHandlerError) {
        do {
            try self.modelContext.save()
        } catch {
            throw DataHandlerError.from(error: error)
        }
    }
    #endif
}

extension RoamDataHandler {
    internal func existingDevice(for id: PersistentIdentifier) async -> Device? {
        if let registered: Device = modelContext.registeredModel(for: id) {
            if registered.isDeleted || registered.deletedAt != nil {
                return nil
            }
            return registered
        }

        let fetchDescriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.persistentModelID == id && $0.deletedAt == nil
            }
        )

        do {
            let model = try await fetchSafer(fetchDescriptor).first

            if model?.isDeleted == true {
                return nil
            }

            return model
        } catch {
            Log.data.notice("Error getting device for id \(id.described(), privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func existingApp(for id: PersistentIdentifier) async -> AppLink? {
        if let registered: AppLink = modelContext.registeredModel(for: id) {
            if registered.isDeleted || registered.deletedAt != nil {
                return nil
            }
            return registered
        }

        let fetchDescriptor = FetchDescriptor<AppLink>(
            predicate: #Predicate {
                $0.persistentModelID == id && $0.deletedAt == nil
            }
        )
        do {
            let data = try await fetchSafer(fetchDescriptor).first

            if data?.isDeleted == true {
                return nil
            }

            return data
        } catch {
            Log.data.notice("Error getting app for id \(id.described(), privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}

extension PersistentIdentifier {
    func described() -> String {
        return String(describing: self)
    }
}

extension RoamDataHandler {
    public func allAppEntities() async throws -> [AppLinkAppEntity] {
        let descriptor = FetchDescriptor<AppLink>(predicate: #Predicate {
             $0.deletedAt == nil
        })

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func allAppEntitiesIncludingDeleted() async throws -> [AppLinkAppEntity] {
        let descriptor = FetchDescriptor<AppLink>(predicate: #Predicate { _ in
            true
        })

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func appEntities(for identifiers: [AppLinkAppEntity.ID], deviceUid: String?) async throws -> [AppLinkAppEntity] {
        let descriptor = FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
            identifiers.contains(appLink.id)
                && (deviceUid == nil || appLink.deviceUid == deviceUid)
                && appLink.deletedAt == nil
        })

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func appEntities(matching string: String, deviceUid: String?) async throws -> [AppLinkAppEntity] {
        let descriptor = FetchDescriptor<AppLink>(predicate: #Predicate<AppLink> { appLink in
            appLink.name.contains(string) &&
                (deviceUid == nil || appLink.deviceUid == deviceUid) &&
                appLink.deletedAt == nil
        })

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func appEntities(deviceUid: String?) async throws -> [AppLinkAppEntity] {
        let descriptor = FetchDescriptor<AppLink>(
            predicate: #Predicate {
                (deviceUid == nil || $0.deviceUid == deviceUid)
                    && $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\AppLink.lastSelected, order: .reverse)]
        )

        let links = try await self.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func deleteAppsForDeviceUdn(udn: String) throws {
        try modelContext.delete(
            model: AppLink.self,
            where: #Predicate {
                $0.deviceUid == udn
            }
        )
    }
}

protocol RefreshClient: Sendable {
    func getId() async throws -> PersistentIdentifier
    func getDeviceInfo() async throws -> DeviceInfo
    func getDeviceCapabilities() async throws -> DeviceCapabilities
    func getDeviceApps() async throws -> [AppLinkAppEntity]
    func getDeviceAppIcon(_ appId: String) async throws -> Data
    func getDeviceIcon() async throws -> Data
}

#if os(watchOS) && !WIDGET
actor WatchOSRefreshClient: RefreshClient {
    let id: PersistentIdentifier
    let location: String

    init(id: PersistentIdentifier, location: String) {
        self.id = id
        self.location = location
    }

    func getId() throws -> PersistentIdentifier {
        return self.id
    }

    func getDeviceInfo() async throws -> DeviceInfo {
        return try await fetchDeviceInfo(location: location)
    }

    func getDeviceCapabilities() async throws -> DeviceCapabilities {
        return try await fetchDeviceCapabilities(location: location)
    }

    func getDeviceApps() async throws -> [AppLinkAppEntity] {
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
    let id: PersistentIdentifier
    let client: ECPWebsocketClient
    let location: String

    init(id: PersistentIdentifier, client: ECPWebsocketClient, location: String) {
        self.id = id
        self.client = client
        self.location = location
    }

    func getId() throws -> PersistentIdentifier {
        return self.id
    }

    func getDeviceInfo() async throws -> DeviceInfo {
        return try await client.getDeviceInfo()
    }

    func getDeviceCapabilities() async throws -> DeviceCapabilities {
        return try await client.getDeviceCapabilities()
    }

    func getDeviceApps() async throws -> [AppLinkAppEntity] {
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

#if !WIDGET
extension RoamDataHandler {
    func refreshDevice(client: any RefreshClient) async {
        let id: PersistentIdentifier
        do {
            id = try await client.getId()
            Log.data.notice("Refreshing device with id \(String(describing: id), privacy: .public)")
        } catch {
             Log.data.error("Failed to refresh device because couldn't get id")
            return
        }
        let lastRefreshed = await self.existingDevice(for: id)?.lastSyncAt ?? .distantPast
        if lastRefreshed.advanced(by: 30) > .now {
            Log.data.notice("Device refresh skipped for id \(String(describing: id), privacy: .public) b/c last refreshed \(lastRefreshed, privacy: .public)")
            return
        } else {
            Log.data.notice("Refreshing device with id \(String(describing: id), privacy: .public) lastRefreshed \(lastRefreshed, privacy: .public)")
        }

        let deviceInfo: DeviceInfo
        do {
            deviceInfo = try await client.getDeviceInfo()
            Log.data.notice("Successfully refreshed device info")
        } catch {
            Log.data.notice("Failed to get device info \(id.described(), privacy: .public), \(error, privacy: .public)")
            return
        }

        if let device = await self.existingDevice(for: id) {
            if deviceInfo.udn != device.udn {
                Log.data.warning("Error: trying to refresh device with udn \(deviceInfo.udn, privacy: .public), but device already has udn \(device.udn, privacy: .public)")
                return
            }

            device.lastOnlineAt = Date.now
            device.lastSyncAt = Date.now

            let udn: String = device.udn

            let descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn && $0.deletedAt == nil
                }
            )

            let deviceApps = (try? await self.fetchSafer(descriptor)) ?? []

            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000.0 > -minRescanInterval,
               deviceApps.allSatisfy({ $0.iconHash != nil }), deviceApps.count > 0
            {
                try? await self.saveSafer()
                Log.data.notice("Returning early from refresh")
                return
            }
            device.lastScannedAt = Date.now

            device.ethernetMAC = deviceInfo.ethernetMac
            device.wifiMAC = deviceInfo.wifiMac
            device.networkType = deviceInfo.networkType
            device.powerMode = deviceInfo.powerMode
            if device.name == getGlobalNewDeviceName() {
                if let newName = deviceInfo.friendlyDeviceName {
                    device.name = newName
                }
            }

            try? await self.saveSafer()
        }

        Log.data.notice("Refreshing capabilities and apps")

        var capabilities: DeviceCapabilities?
        do {
            capabilities = try await client.getDeviceCapabilities()
            Log.data.notice("Successful refreshed capabilities")
        } catch {
            Log.data.error("Error getting capabilities \(error, privacy: .public)")
        }

        var sortedApps: [AppLinkAppEntity]?
        do {
            sortedApps = try await client.getDeviceApps()
            Log.data.notice("Successfully refreshed device apps")
        } catch {
            Log.data.error("Error getting device apps \(error, privacy: .public)")
        }

        var deviceNeedsIcon = false
        var appsNeedingIcons: [String] = []
        if let device = await self.existingDevice(for: id) {
            deviceNeedsIcon = device.deviceIconHash == nil
            if let capabilities {
                device.rtcpPort = capabilities.rtcpPort
                device.supportsDatagram = capabilities.supportsDatagram
            }

            let udn: String = device.udn
            let descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn && $0.deletedAt == nil
                }
            )

            let deviceApps = (try? await self.fetchSafer(descriptor)) ?? []

            if let sortedApps {
                // Remove apps from device that aren't in fetchedApps
                let deletedApps = deviceApps.filter { existingApp in
                    return !sortedApps.contains { $0.id == existingApp.id }
                }
                for app in deletedApps {
                    app.deletedAt = .now
                }
                var deviceApps = deviceApps.filter { existingApp in
                    return sortedApps.contains { $0.id == existingApp.id }
                }
                deviceApps.forEach { existingApp in
                    existingApp.deviceSortOrder = sortedApps.firstIndex(where: { $0.id == existingApp.id }) ?? nil
                }

                // Sync App Names
                for app in deviceApps where (app.lastSyncAt ?? .distantPast).advanced(by: 3600 * 24) < .now {
                    app.name = (sortedApps.first { $0.id == app.id })?.name ?? app.name
                }

                // Add new apps to device
                for (index, app) in sortedApps.enumerated() where !deviceApps.contains(where: { $0.id == app.id }) {
                    let al = AppLink(id: app.id, type: app.type, name: app.name, deviceUid: device.udn, deviceSortOrder: index)
                    modelContext.insert(al)
                    deviceApps.append(al)
                }

                // Fetch icons for apps in deviceApps
                for app in deviceApps where app.iconHash == nil || (app.lastSyncAt ?? .distantPast).advanced(by: 3600 * 24) < .now {
                    appsNeedingIcons.append(app.id)
                }
            }

            try? await self.saveSafer()
        }

        var deviceIcon: Data?
        if deviceNeedsIcon {
            Log.data.notice("Getting icon for device")
            do {
                let newIcon = try await client.getDeviceIcon()
                deviceIcon = newIcon
            } catch {
                Log.data.warning("Error getting device icon \(error, privacy: .public)")
            }
        }

        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                Log.data.notice("Getting device app icon for id \(appId, privacy: .public)")
                let iconData = try await client.getDeviceAppIcon(appId)
                Log.data.notice("Successfully refreshed device app icon")
                appIcons[appId] = iconData
            } catch {
                Log.data.error("Error getting device app icon \(error, privacy: .public)")
            }
        }

        if let device = await self.existingDevice(for: id) {
            let udn: String? = device.udn

            let descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn && $0.deletedAt == nil
                }
            )

            let deviceApps = (try? await self.fetchSafer(descriptor)) ?? []

            if let icon = deviceIcon {
                let iconHash = fastHashData(data: icon)
                do {
                    try storeIconToDisk(iconData: icon, hash: iconHash)
                    device.deviceIconHash = iconHash
                } catch {
                    Log.data.warning("Error storing device icon \(error, privacy: .public)")
                }
            }
            for app in appIcons {
                if let deviceApp = deviceApps.first(where: { $0.id == app.key }) {
                    let iconHash = fastHashData(data: app.value)
                    do {
                        try storeIconToDisk(iconData: app.value, hash: iconHash)
                        deviceApp.iconHash = iconHash
                        deviceApp.lastSyncAt = .now
                    } catch {
                        Log.data.warning("Error storing app icon \(error, privacy: .public)")
                    }
                }
            }
            try? await self.saveSafer()
        }

        await deleteInPast()
    }
}

@ModelActor
actor MessageDataHandler {
    @MainActor
    static let shared: MessageDataHandler = .init(modelContainer: getSharedModelContainer())

    let semaphore: AsyncLock = AsyncLock()

    @discardableResult
    public func refreshMessagesIfExpectingNewMessages() async -> Int {
        Log.data.notice("Refreshing messages")
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate {
                $0.fetchedBackend == true
            },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        var lastMessage: Message?
        do {
            lastMessage = try await self.fetchSafer(descriptor).last
        } catch {
            Log.data.notice("Error loading messages \(error, privacy: .public)")
        }

        if lastMessage == nil {
            Log.data.notice("Not refreshing messages with last message nil")
            return 0
        }
        return await self.refreshMessages(
            viewed: false
        )
    }

    @discardableResult
    public func refreshMessages(viewed: Bool) async -> Int {
        Log.data.notice("Querying for message to fetch new")
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { model in
                model.fetchedBackend == true
            }
        )
        descriptor.sortBy = [SortDescriptor(\Message.id, order: .reverse)]
        descriptor.fetchLimit = 1
        let latestMessageId = (try? await self.fetchSafer(descriptor))?.first?.id

        Log.data.notice("Refreshing messages with last message \(String(describing: latestMessageId), privacy: .public)")

        return await withTaskGroup(of: Int.self) { taskGroup in
            taskGroup.addTask {
                await self.trySendMessages()
                return 0
            }
            await Task.yield()
            taskGroup.addTask {
                return await self.refreshExternalMessages(latestMessageId: latestMessageId, viewed: viewed)
            }
            var total = 0
            while !taskGroup.isEmpty {
                total += await taskGroup.next() ?? 0
            }
            return total
        }
    }

    public func getSendableMessages() async throws -> [Message] {
        Log.data.notice("Getting sendable messages")
        let tenPast = Date.now - 10
        let distantPast = Date.distantPast
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { model in
                model.fetchedBackend == false && (
                    (model.lastSendAttempt ?? distantPast) < tenPast
                )
            }
        )
        let foundModels = try await self.fetchSafer(descriptor)
        for model in foundModels {
            model.lastSendAttempt = Date.now
        }
        Log.data.notice("Got \(foundModels.count, privacy: .public) sendable messages")
        try await self.saveSafer()
        return foundModels
    }

    public func trySendMessages() async {
        do {
            try await semaphore.lock()
        } catch {
            return
        }
        defer {
            semaphore.unlock()
        }
        let messages: [Message]
        do {
            messages = try await self.getSendableMessages()
        } catch {
            Log.backend.notice("Error getting messages to send \(error, privacy: .public)")
            return
        }
        for message in messages {
            do {
                let messageResult = try await sendMessageDirect(message: message.message, attachment: message.unsentAttachment).get()
                message.id = messageResult.id
                message.lastSendAttempt = Date.distantFuture
                message.cycleAttachments(messageResult.attachments?.compactMap({ a in
                    let hash = fastHashData(data: a.data)
                    do {
                        try storeAttachmentToDisk(attachmentData: a.data, hash: hash, filename: a.filename)
                    } catch {
                        Log.backend.error("Error saving attachment to disk \(error, privacy: .public)")
                        return nil
                    }
                    return Message.SentAttachment(id: a.id, dataHash: hash, dataSize: Int64(a.data.count), filename: a.filename, mimetype: a.contentType)
                }) ?? [])
                try await self.saveSafer()
            } catch {
                Log.backend.notice("Error sending message \(message.id, privacy: .public), \(error, privacy: .public)")
                message.lastSendAttempt = nil
                try? await self.saveSafer()
            }
        }
    }

    public func sendChatMessage(message: String, attachment: AttachmentUpload?) async throws {
        let nonce = String(Int64.random(in: 0..<Int64.max))
        let id = generateDiscordSnowflake(Date.now.addingTimeInterval(1))
        Log.backend.info("Inserting pending message to send queue: \(message, privacy: .public)")
        self.modelContext.insert(Message(
            id: id,
            message: message,
            author: .me,
            fetchedBackend: false,
            viewed: true,
            unsentAttachment: attachment,
            nonce: nonce
        ))
        try await self.saveSafer()
        Log.backend.info("Saved message to send queue: \(message, privacy: .public), id: \(id, privacy: .public)")
        await self.trySendMessages()
    }

    public func refreshExternalMessages(latestMessageId: String?, viewed: Bool) async -> Int {
        do {
            try await self.semaphore.lock()
        } catch {
            return 0
        }
        defer {
            self.semaphore.unlock()
        }
        do {
            var count = 0
            do {
                let updates = try await getMessagingUpdates(after: latestMessageId)
                Log.backend.notice("Got \(updates.messages.count) new messages")
                let newMessages = updates.messages.map { Message($0) }
                UserDefaults.standard.set(updates.presence.lastSupportTyping?.timeIntervalSince1970, forKey: UserDefaultKeys.lastSupportTypingTime)
                UserDefaults.standard.set(updates.presence.lastSelfTyping?.timeIntervalSince1970, forKey: UserDefaultKeys.lastTypingTime)

                for message in newMessages {
                    message.viewed = viewed

                    let id = message.id
                    let existingMessageDescriptor = FetchDescriptor<Message>(
                        predicate: #Predicate { $0.id == id }
                    )

                    let existingMessages = try await self.fetchSafer(existingMessageDescriptor)
                    for message in existingMessages {
                        modelContext.delete(message)
                    }
                    modelContext.insert(message)

                    message.triggerAction()
                }
                count = newMessages.count

                let savingMessages = try await self.fetchSafer(FetchDescriptor<Message>(
                    predicate: #Predicate { $0.fetchedBackend == false || $0.lastSendAttempt != nil }
                ))
                for message in savingMessages {
                    modelContext.delete(message)
                }
            } catch {
                Log.data.error("Error getting latest messages \(error, privacy: .public)")
            }
            if viewed == true {
                let unviewedMessagesDescriptor = FetchDescriptor<Message>(predicate: #Predicate {
                    !$0.viewed
                })
                let unviewedMessages = try modelContext.fetch(unviewedMessagesDescriptor)
                for message in unviewedMessages {
                    message.viewed = true
                }
            }

            try await self.saveSafer()

            return count
        } catch {
            Log.data.error("Error refreshing messages \(error, privacy: .public)")
            return 0
        }
    }
}

extension MessageDataHandler {
    #if !os(macOS)
    func fetchSafer<T>(_ descriptor: FetchDescriptor<T>) async throws -> [T] {
        let assertion = await QRunInBackgroundAssertion(name: "MessagingFetchSafer")
        do {
            if await !assertion.isReleased() {
                let res = try self.modelContext.fetch(descriptor)
                await assertion.release()
                return res
            }
            await assertion.release()
        } catch {
            await assertion.release()
            throw error
        }
        throw DataHandlerError.suspending
    }
    #else
    func fetchSafer<T>(_ descriptor: FetchDescriptor<T>) async throws -> [T] {
        return try self.modelContext.fetch(descriptor)
    }
    #endif

    #if !os(macOS)
    func saveSafer() async throws {
        let assertion = await QRunInBackgroundAssertion(name: "MessagingSaveSafer")
        do {
            if await !assertion.isReleased() {
                try self.modelContext.save()
            } else {
                throw DataHandlerError.suspending
            }
        } catch {
            await assertion.release()
            throw error
        }
        await assertion.release()
    }
    #else
    func saveSafer() async throws {
        try self.modelContext.save()
    }
    #endif
}
#endif

@discardableResult
func storeUserFileToDisk(data: Data, filename: String, path: [String]) throws -> URL {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
        throw DataHandlerError.noContainerURL
    }

    var iconDirectoryURL = containerURL
    for path in path {
        iconDirectoryURL = iconDirectoryURL.appendingPathComponent(path, isDirectory: true)
    }

    if !FileManager.default.fileExists(atPath: iconDirectoryURL.path) {
        try FileManager.default.createDirectory(at: iconDirectoryURL, withIntermediateDirectories: true)
    }

    let iconFileURL = iconDirectoryURL.appendingPathComponent(filename)

    // Write data atomically to prevent corruption
    do {
        try data.write(to: iconFileURL, options: .atomic)
    } catch let error as NSError {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            throw DataHandlerError.noSpaceOnDisk
        }
        throw error
    } catch {
        throw error
    }
    return iconFileURL
}

@discardableResult
func storeIconToDisk(iconData: Data, hash: String) throws -> URL {
    return try storeUserFileToDisk(data: iconData, filename: hash, path: ["roku-icons"])
}

@discardableResult
func storeAttachmentToDisk(attachmentData: Data, hash: String, filename: String) throws -> URL {
    return try storeUserFileToDisk(data: attachmentData, filename: filename, path: ["message-attachments", hash])
}

func loadAttachmentFromDisk(hash: String, filename: String) throws -> Data {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
        throw DataHandlerError.noContainerURL
    }

    let iconDirectoryURL = containerURL
        .appendingPathComponent("message-attachments", isDirectory: true)
        .appendingPathComponent(hash, isDirectory: true)

    if !FileManager.default.fileExists(atPath: iconDirectoryURL.path) {
        try FileManager.default.createDirectory(at: iconDirectoryURL, withIntermediateDirectories: true)
    }

    let iconFileURL = iconDirectoryURL.appendingPathComponent(filename)

    return try Data(contentsOf: iconFileURL)
}
