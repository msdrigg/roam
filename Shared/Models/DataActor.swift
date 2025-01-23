import Foundation
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "DataManagement"
)

func getGlobalNewDeviceName() -> String {
    return String(localized: "New device")
}

@ModelActor
public actor DataHandler {
    static let hardDeleteTimeout: TimeInterval = 3600

    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DataHandler.self)
    )

    private let minRescanInterval: TimeInterval = 30

    private func allDevices() throws -> [Device] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]
        descriptor.propertiesToFetch = [
            \.lastSentToWatch, \.udn
        ]
        let links = try modelContext.fetchSafer(
            descriptor
        )
        return links
    }

    func setSelectedApp(_ appId: PersistentIdentifier) {
        DataHandler.logger.info("Updating selectedAt for app with id \(appId.described(), privacy: .public)")

        if let appLink = modelContext.existingApp(for: appId) {
            DataHandler.logger.info("Setting appId selected to now")
            appLink.lastSelected = Date.now
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.error("Error marking app as selected \(appLink.id, privacy: .public)")
            }
        }
    }

    func setSelectedDevice(_ id: PersistentIdentifier) {
        DataHandler.logger.info("Updating selectedAt for device with id \(String(describing: id), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            DataHandler.logger.info("Found device to update with location \(device.location, privacy: .public)")
            device.lastSelectedAt = Date.now
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.error("Error marking device as selected \(device.location, privacy: .public)")
            }
        }
    }

    func updateDevice(_ id: PersistentIdentifier, name: String, location: String, udn: String) {
        DataHandler.logger.info("Updating device at \(location, privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            DataHandler.logger.info("Found device to update with id \(id.described(), privacy: .public))")
            device.location = location
            device.name = name
            device.udn = udn
            device.lastSentToWatch = nil
            do {
                try modelContext.save()
            } catch {
                Self.logger.warning("Error updating device at location \(location, privacy: .public)")
            }
        }
        DataHandler.logger.info("Updated device at \(location, privacy: .public)")
    }

    @discardableResult
    func addOrReplaceDevice(location: String, friendlyDeviceName: String, udn: String) -> PersistentIdentifier? {
        if let device = deviceForUdn(udn: udn) {
            device.location = location
            device.name = friendlyDeviceName
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.warning("Error updating device fields \(error, privacy: .public)")
            }
            return device.persistentModelID
        }
        var lastOnlineAt: Date? = Date.now

        if udn.hasPrefix("roam:") {
            lastOnlineAt = nil
        }

        DataHandler.logger.info("Adding device at \(location, privacy: .public)")
        let device = Device(
            name: friendlyDeviceName,
            location: location,
            lastOnlineAt: lastOnlineAt,
            udn: udn
        )
        modelContext.insert(device)

        do {
            try modelContext.save()
            DataHandler.logger.info("Added device \(String(describing: device.persistentModelID), privacy: .public)")
            return device.persistentModelID
        } catch {
            DataHandler.logger.warning("Error adding device at \(location, privacy: .public), \(error, privacy: .public)")
            return nil
        }
    }

    func sentToWatch(deviceId: PersistentIdentifier) {
        do {
            if let device = modelContext.existingDevice(for: deviceId) {
                device.lastSentToWatch = Date.now
                try modelContext.save()
            }
        } catch {
            DataHandler.logger.warning("Error marking device \(deviceId.described(), privacy: .public) as sent to watch \(error, privacy: .public)")
        }
    }

    func watchPossiblyDead() {
        let devices = (try? allDevices()) ?? []
        for device in devices {
            device.lastSentToWatch = nil
        }
        do {
            try modelContext.save()
        } catch {
            DataHandler.logger.warning("Error marking devices as not sent to watch \(error, privacy: .public)")
        }
    }

    func deleteInPast() async {
        DataHandler.logger.info("Hard deleting devices")
        let deleteBefore = Date.now - Self.hardDeleteTimeout
        let distantFuture = Date.distantFuture
        do {
            var descriptor = FetchDescriptor<Device>(predicate: #Predicate {
                $0.deletedAt ?? distantFuture < deleteBefore
            })
            descriptor.propertiesToFetch = [\.name, \.udn, \.location]
            let models = try modelContext.fetchSafer(descriptor)

            for model in models {
                Self.logger.info("Deleteing device and apps \(model.location, privacy: .public) with name \(model.name, privacy: .public)")
                do {
                    try deleteAppsForDeviceUdn(udn: model.udn)
                } catch {
                    Self.logger.warning("Error deleting past apps for device \(model.udn, privacy: .public) \(error, privacy: .public)")
                }
                modelContext.delete(model)
            }

            try modelContext.save()
        } catch {
            Self.logger.warning("Error deleting past devices \(error, privacy: .public)")
        }
    }

    func delete(_ id: PersistentIdentifier) async throws {
        DataHandler.logger.info("Soft deleting device \(String(describing: id), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            device.deletedAt = .now
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("Error deleting device with id \(id.described(), privacy: .public)")
                return
            }
        }

        await deleteInPast()
    }

    private func deviceForUdnUnchecked(udn: String) -> Device? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.udn == udn
            }
        )
        matchingIds.fetchLimit = 1
        matchingIds.includePendingChanges = true
        matchingIds.propertiesToFetch = [
            \.udn, \.location, \.lastOnlineAt,
             \.lastSelectedAt, \.name, \.deletedAt,
             \.lastSentToWatch, \.lastScannedAt,
             \.ethernetMAC, \.rtcpPort,
             \.supportsDatagram, \.wifiMAC,
             \.networkType, \.powerMode
        ]
        do {
            let matchingIds = try modelContext.fetchIdentifiers(matchingIds)

            if let matchingPid = matchingIds.first {
                if let device = modelContext.existingDevice(for: matchingPid) {
                    return device
                }
            }
        } catch {
            DataHandler.logger.error("Error checking if device exists \(udn, privacy: .public): \(error, privacy: .public)")
        }
        return nil
    }

    private func deviceForUdn(udn: String) -> Device? {
        do {
            return try catchObjc {
                return deviceForUdnUnchecked(udn: udn)
            }
        } catch {
            Self.logger.warning("Objc error getting device \(error, privacy: .public)")
            return nil
        }
    }

    func deviceEntityForUdn(udn: String) -> DeviceAppEntity? {
        return deviceForUdn(udn: udn)?.toAppEntity()
    }

    func deviceExists(id: String) -> Bool {
        deviceForUdn(udn: id) != nil
    }

    func fetchSelectedDeviceAppEntity() -> DeviceAppEntity? {
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
        descriptor.propertiesToFetch = [\.name, \.location, \.udn, \.wifiMAC, \.ethernetMAC, \.lastSelectedAt, \.lastSentToWatch, \.lastOnlineAt, \.lastScannedAt, \.deletedAt]

        let selectedDevice: Device? = try? modelContext.fetchSafer(descriptor).first

        return selectedDevice?.toAppEntity()
    }
}

extension DataHandler {
    public func deviceEntities(for identifiers: [DeviceAppEntity.ID]) throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(predicate: #Predicate {
            identifiers.contains($0.udn) && $0.deletedAt == nil
        })

        descriptor.propertiesToFetch = [\.name, \.location, \.udn, \.wifiMAC, \.ethernetMAC, \.lastSelectedAt, \.lastSentToWatch, \.lastOnlineAt, \.lastScannedAt, \.deletedAt]

        let links = try modelContext.fetchSafer(descriptor)

        return links.map { $0.toAppEntity() }
    }

    public func deviceEntities(matching string: String) throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(predicate: #Predicate {
            $0.name.contains(string) && $0.deletedAt == nil
        })

        descriptor.propertiesToFetch = [\.name, \.location, \.udn, \.wifiMAC, \.ethernetMAC, \.lastSelectedAt, \.lastSentToWatch, \.lastOnlineAt, \.lastScannedAt, \.deletedAt]

        let links = try modelContext.fetchSafer(descriptor)
        return links.map { $0.toAppEntity() }
    }

    public func allDeviceEntitiesIncludingDeleted() throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { _ in
                true
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]
        descriptor.propertiesToFetch = [\.name, \.location, \.udn, \.wifiMAC, \.ethernetMAC, \.lastSelectedAt, \.lastSentToWatch, \.lastOnlineAt, \.lastScannedAt, \.deletedAt]

        let links = try modelContext.fetchSafer(
            descriptor
        )
        return links.map { $0.toAppEntity() }
    }

    public func allDeviceEntities() throws -> [DeviceAppEntity] {
        var descriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse),
            SortDescriptor(\Device.lastOnlineAt, order: .reverse),
        ]
        descriptor.propertiesToFetch = [\.name, \.location, \.udn, \.wifiMAC, \.ethernetMAC, \.lastSelectedAt, \.lastSentToWatch, \.lastOnlineAt, \.lastScannedAt, \.deletedAt]

        let links = try modelContext.fetchSafer(
            descriptor
        )
        return links.map { $0.toAppEntity() }
    }

    public func loadTestData() throws {
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

        try modelContext.save()
        #endif
    }

    public func clearData() throws {
        try modelContext.delete(model: Device.self)
        try modelContext.delete(model: AppLink.self)
        try modelContext.delete(model: Message.self)
    }
}

public extension ModelContext {
    func fetchSafer<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        return try catchObjc {
            return try self.fetch(descriptor)
        }
    }
}

extension ModelContext {
    internal func existingDevice(for id: PersistentIdentifier) -> Device? {
        if let registered: Device = registeredModel(for: id) {
            if registered.isDeleted || registered.deletedAt != nil {
                return nil
            }
            return registered
        }

        var fetchDescriptor = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.persistentModelID == id && $0.deletedAt == nil
            }
        )
        fetchDescriptor.propertiesToFetch = [
            \.udn, \.location, \.lastOnlineAt,
             \.lastSelectedAt, \.name, \.deletedAt,
             \.lastSentToWatch, \.lastScannedAt,
             \.ethernetMAC, \.rtcpPort,
             \.supportsDatagram, \.wifiMAC,
             \.networkType, \.powerMode
        ]

        do {
            let model = try fetchSafer(fetchDescriptor).first

            if model?.isDeleted == true {
                return nil
            }

            return model
        } catch {
            logger.info("Error getting device for id \(id.described(), privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func existingApp(for id: PersistentIdentifier) -> AppLink? {
        if let registered: AppLink = registeredModel(for: id) {
            if registered.isDeleted {
                return nil
            }
            return registered
        }

        var fetchDescriptor = FetchDescriptor<AppLink>(
            predicate: #Predicate {
                $0.persistentModelID == id
            }
        )
        fetchDescriptor.propertiesToFetch = [\.id, \.name, \.lastSelected, \.deviceUid, \.type]
        do {
            let data = try fetchSafer(fetchDescriptor).first

            if data?.isDeleted == true {
                return nil
            }

            return data
        } catch {
            logger.info("Error getting app for id \(id.described(), privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}

extension PersistentIdentifier {
    func described() -> String {
        return String(describing: self)
    }
}

public struct DataHandlerKey: EnvironmentKey {
  public static let defaultValue: @Sendable () async -> DataHandler? = { nil }
}

extension DataHandler {
    public func allAppEntities() throws -> [AppLinkAppEntity] {
        var descriptor = FetchDescriptor<AppLink>(predicate: #Predicate { _ in
            true
        })
        descriptor.propertiesToFetch = [\.name, \.id, \.type, \.icon]

        let links = try modelContext.fetchSafer(descriptor)
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func appEntities(for identifiers: [AppLinkAppEntity.ID], deviceUid: String?) throws -> [AppLinkAppEntity] {

        var descriptor = FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
            identifiers.contains(appLink.id) && (deviceUid == nil || appLink.deviceUid == deviceUid)
        })
        descriptor.propertiesToFetch = [\.name, \.id, \.type, \.icon]

        let links = try modelContext.fetchSafer(descriptor)
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func appEntities(matching string: String, deviceUid: String?) throws -> [AppLinkAppEntity] {
        var descriptor = FetchDescriptor<AppLink>(predicate: #Predicate<AppLink> { appLink in
            appLink.name.contains(string) && (deviceUid == nil || appLink.deviceUid == deviceUid)
        })

        descriptor.propertiesToFetch = [\.name, \.id, \.type, \.icon]
        let links = try modelContext.fetchSafer(descriptor)
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func appEntities(deviceUid: String?) throws -> [AppLinkAppEntity] {
        var descriptor = FetchDescriptor<AppLink>(
            predicate: #Predicate {
                deviceUid == nil || $0.deviceUid == deviceUid
            },
            sortBy: [SortDescriptor(\AppLink.lastSelected, order: .reverse)]
        )

        descriptor.propertiesToFetch = [\.name, \.id, \.type, \.icon]

        let links = try modelContext.fetchSafer(descriptor)
        return links.map { $0.toAppEntityWithIcon() }
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

extension DataHandler {
    func refreshDevice(_ id: PersistentIdentifier) async {
        Self.logger.info("Refreshing device with id \(String(describing: id), privacy: .public)")
        guard let location = (modelContext.existingDevice(for: id))?.location else {
            DataHandler.logger.error("Trying to refresh device that doeesn't exist \(String(describing: id), privacy: .public)")
            return
        }
        #if !os(watchOS)
        let ecpSession: ECPWebsocketClient
        do {
            guard let location = URL(string: location) else {
                throw APIError.badURLError(location)
            }
            ecpSession = ECPWebsocketClient(location: location)
            await ecpSession.start()
        } catch {
            Self.logger.warning("Error refreshing device b/c no ECP Session: \(error, privacy: .public)")
            return
        }
        defer {
            Task {
                await ecpSession.cancel()
            }
        }
        #endif

        #if os(watchOS)
        guard let deviceInfo = await fetchDeviceInfo(location: location) else {
            Self.logger.warning("Error getting device info")
            return
        }
        Self.logger.info("Successfully refreshed device info")
        #else
        let deviceInfo: DeviceInfo
        do {
            deviceInfo = try await ecpSession.getDeviceInfo()
            Self.logger.info("Successfully refreshed device info")
        } catch {
            Self.logger.info("Failed to get device info \(location, privacy: .public), \(error, privacy: .public)")
            return
        }
        #endif

        if let device = modelContext.existingDevice(for: id) {
            if device.udn.starts(with: "roam:newdevice-") {
                device.udn = deviceInfo.udn
            } else if deviceInfo.udn != device.udn {
                Self.logger.warning("Error: trying to refresh device with udn \(deviceInfo.udn, privacy: .public), but device already has udn \(device.udn, privacy: .public)")
                return
            }

            device.lastOnlineAt = Date.now

            let udn: String? = device.udn

            var descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn
                }
            )

            descriptor.propertiesToFetch = [\.name, \.id, \.type, \.icon]
            let deviceApps = (try? modelContext.fetchSafer(descriptor)) ?? []

            if (device.lastScannedAt?.timeIntervalSinceNow) ?? -10000 > -minRescanInterval,
               deviceApps.allSatisfy({ $0.icon != nil }), deviceApps.count > 0
            {
                try? modelContext.save()
                DataHandler.logger.info("Returning early from refresh")
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

            try? modelContext.save()
        }

        DataHandler.logger.info("Refreshing capabilities and apps")

        var capabilities: DeviceCapabilities?
        do {
            #if os(watchOS)
            capabilities = try await fetchDeviceCapabilities(location: location)
            #else
            capabilities = try await ecpSession.getDeviceCapabilities()
            #endif
            Self.logger.info("Successful refreshed capabilities")
            Self.logger.info("Successful refreshed capabilities")
        } catch {
            DataHandler.logger.error("Error getting capabilities \(error, privacy: .public)")
        }

        var sortedApps: [AppLinkAppEntity]?
        do {
            #if os(watchOS)
            sortedApps = try await fetchDeviceApps(location: location)
            #else
            sortedApps = try await ecpSession.getDeviceApps()
            #endif
            Self.logger.info("Successfully refreshed device apps")
        } catch {
            DataHandler.logger.error("Error getting device apps \(error, privacy: .public)")
        }

        var deviceNeedsIcon = false
        var appsNeedingIcons: [String] = []
        if let device = modelContext.existingDevice(for: id) {
            deviceNeedsIcon = device.deviceIcon == nil
            if let capabilities {
                device.rtcpPort = capabilities.rtcpPort
                device.supportsDatagram = capabilities.supportsDatagram
            }

            let udn: String = device.udn
            var descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn
                }
            )
            descriptor.propertiesToFetch = [\.id, \.name, \.deviceUid, \.type, \.icon]

            let deviceApps = (try? modelContext.fetchSafer(descriptor)) ?? []

            if let sortedApps {
                // Remove apps from device that aren't in fetchedApps
                var deviceApps = deviceApps.filter { existingApp in
                    return sortedApps.contains { $0.id == existingApp.id }
                }
                deviceApps.forEach { existingApp in
                    existingApp.deviceSortOrder = sortedApps.firstIndex(where: { $0.id == existingApp.id }) ?? nil
                }

                // Add new apps to device
                for (index, app) in sortedApps.enumerated() where !deviceApps.contains(where: { $0.id == app.id }) {
                    let al = AppLink(id: app.id, type: app.type, name: app.name, deviceUid: device.udn, deviceSortOrder: index)
                    modelContext.insert(al)
                    deviceApps.append(al)
                }

                // Fetch icons for apps in deviceApps
                for app in deviceApps where app.icon == nil {
                    appsNeedingIcons.append(app.id)
                }
            }

            try? modelContext.save()
        }

        var deviceIcon: Data?
        if deviceNeedsIcon {
            DataHandler.logger.info("Getting icon for device \(location, privacy: .public)")
            do {
                deviceIcon = try await fetchDeviceIcon(location: location)
            } catch {
                DataHandler.logger.warning("Error getting device icon \(error, privacy: .public)")
            }
        }

        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                DataHandler.logger.error("Getting device app icon for id \(appId, privacy: .public)")
                #if os(watchOS)
                let iconData = try await fetchAppIcon(location: location, appId: appId)
                #else
                let iconData = try await ecpSession.getDeviceAppIcon(appId)
                #endif
                Self.logger.info("Successfully refreshed device app icon")
                appIcons[appId] = iconData
            } catch {
                DataHandler.logger.error("Error getting device app icon \(error, privacy: .public)")
            }
        }

        if let device = modelContext.existingDevice(for: id) {
            let udn: String? = device.udn

            var descriptor = FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    $0.deviceUid == udn
                }
            )
            descriptor.propertiesToFetch = [\.icon, \.id]

            let deviceApps = (try? modelContext.fetchSafer(descriptor)) ?? []

            if let icon = deviceIcon {
                device.deviceIcon = icon
            }
            for app in appIcons {
                if let deviceApp = deviceApps.first(where: { $0.id == app.key }) {
                    deviceApp.icon = app.value
                }
            }
            try? modelContext.save()
        }

        await deleteInPast()
    }
}

#if !WIDGET
extension DataHandler {
    @discardableResult
    public func refreshMessagesIfExpectingNewMessages() async -> Int {
        Self.logger.info("Refreshing messages")
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate {
                $0.fetchedBackend == true
            },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id]

        let lastMessage = try? modelContext.fetchSafer(descriptor).last

        let lastMessageId = lastMessage?.id
        Self.logger.info("Refreshing messages with last message \(String(describing: lastMessage?.id), privacy: .public)")
        if lastMessage == nil {
            return 0
        }
        return await self.refreshMessages(
            latestMessageId: lastMessageId,
            viewed: false
        )
    }

    @discardableResult
    public func refreshMessages(latestMessageId: String?, viewed: Bool) async -> Int {
        do {
            var count = 0
            do {
                let newMessages = (try await getMessages(after: latestMessageId)).map { Message($0) }

                for message in newMessages {
                    message.viewed = viewed
                    modelContext.insert(message)
                }
                count = newMessages.count
            } catch {
                DataHandler.logger.error("Error getting latest messages \(error, privacy: .public)")
            }

            DataHandler.logger.info("Starting delete")
            var descriptor = FetchDescriptor(
                predicate: #Predicate<Message> { model in
                    !model.fetchedBackend
                }
            )
            descriptor.propertiesToFetch = []
            let foundModels = try modelContext.fetchSafer(descriptor)
            for model in foundModels {
                modelContext.delete(model)
            }
            DataHandler.logger.info("Ending delete")

            if viewed == true {
                let unviewedMessagesDescriptor = FetchDescriptor<Message>(predicate: #Predicate {
                    !$0.viewed
                })
                let unviewedMessages = try modelContext.fetch<Message>(unviewedMessagesDescriptor)
                for message in unviewedMessages {
                    message.viewed = true
                }
            }

            try modelContext.save()

            return count
        } catch {
            DataHandler.logger.error("Error refreshing messages \(error, privacy: .public)")
            return 0
        }
    }
}
#endif

func saveDevice(
    existingDeviceId modelId: PersistentIdentifier,
    existingUDN: String,
    newIP deviceIP: String,
    newDeviceName deviceName: String,
    dataHandler: DataHandler
) async {
    // Try to get device id
    // Watchos can't check tcp connection, so just do the request
    let cleanedString = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
    let deviceUrl = addSchemeAndPort(to: cleanedString)
    logger.info("Getting device url \(deviceUrl, privacy: .public)")
    // Save device id and location early
    await dataHandler.updateDevice(
        modelId, name: deviceName, location: deviceUrl, udn: existingUDN
    )

    #if os(watchOS)
    let deviceInfo = await fetchDeviceInfo(location: deviceUrl)
    #else
    var deviceInfo: DeviceInfo?
    do {
        guard let url = URL(string: deviceUrl) else {
            return
        }
        deviceInfo = try await ECPWebsocketClient(location: url).oneOff { session in
            return try await session.getDeviceInfo()
        }
    } catch {
        logger.error("Error creating ECPSession getting device info: \(error, privacy: .public)")
        return
    }
    #endif
    logger.info("Got device info to save device")

    // If we get a device with a different UDN, replace the device
    if let udn = deviceInfo?.udn, udn != existingUDN {
        do {
            try await dataHandler.delete(modelId)
            await dataHandler.addOrReplaceDevice(
                location: deviceUrl, friendlyDeviceName: deviceName, udn: udn
            )

        } catch {
            DataHandler.logger.error("Error saving device \(error, privacy: .public)")
        }
        return
    }

    DataHandler.logger.info("Saving device \(deviceUrl) with id \(String(describing: modelId), privacy: .public)")
    await dataHandler.updateDevice(
        modelId,
        name: deviceName,
        location: deviceUrl,
        udn: existingUDN
    )
    DataHandler.logger.info("Saved device \(deviceUrl, privacy: .public)")
}
