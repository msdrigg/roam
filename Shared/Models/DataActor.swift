import Foundation
import OSLog
import SwiftData
import SwiftUI

#if swift(>=6.0)
    #warning("Reevaluate whether this decoration is necessary.")
#endif
nonisolated(unsafe) private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "DataManagement"
)

@ModelActor
public actor DataHandler {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DataHandler.self)
    )

    // Only refresh every 1 hour
    private let minRescanInterval: TimeInterval = 3600

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
        DataHandler.logger.info("Updating selectedAt for app with id \(appId.described())")

        if let appLink = modelContext.existingApp(for: appId) {
            DataHandler.logger.info("Setting appId selected to now")
            appLink.lastSelected = Date.now
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.error("Error marking app as selected \(appLink.id)")
            }
        }
    }

    func setSelectedDevice(_ id: PersistentIdentifier) {
        DataHandler.logger.info("Updating selectedAt for device with id \(String(describing: id))")
        if let device = modelContext.existingDevice(for: id) {
            DataHandler.logger.info("Found device to update with location \(device.location)")
            device.lastSelectedAt = Date.now
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.error("Error marking device as selected \(device.location)")
            }
        }
    }

    func updateDevice(_ id: PersistentIdentifier, name: String, location: String, udn: String) {
        DataHandler.logger.info("Updating device at \(location)")
        if let device = modelContext.existingDevice(for: id) {
            DataHandler.logger.info("Found device to update with id \(id.described()))")
            device.location = location
            device.name = name
            device.udn = udn
            device.lastSentToWatch = nil
            do {
                try modelContext.save()
            } catch {
                Self.logger.warning("Error updating device at location \(location)")
            }
        }
        DataHandler.logger.info("Updated device at \(location)")
    }

    @discardableResult
    func addOrReplaceDevice(location: String, friendlyDeviceName: String, udn: String) -> PersistentIdentifier? {
        if let device = deviceForUdn(udn: udn) {
            device.location = location
            device.name = friendlyDeviceName
            do {
                try modelContext.save()
            } catch {
                DataHandler.logger.warning("Error updating device fields \(error)")
            }
            return device.persistentModelID
        }
        var lastOnlineAt: Date? = Date.now

        if udn.hasPrefix("roam:") {
            lastOnlineAt = nil
        }

        DataHandler.logger.info("Adding device at \(location)")
        let device = Device(
            name: friendlyDeviceName,
            location: location,
            lastOnlineAt: lastOnlineAt,
            udn: udn
        )
        modelContext.insert(device)

        do {
            try modelContext.save()
            DataHandler.logger.info("Added device \(String(describing: device.persistentModelID))")
            return device.persistentModelID
        } catch {
            DataHandler.logger.warning("Error adding device at \(location), \(error)")
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
            DataHandler.logger.warning("Error marking device \(deviceId.described()) as sent to watch \(error)")
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
            DataHandler.logger.warning("Error marking devices as not sent to watch \(error)")
        }
    }

    func deleteInPast() async {
        DataHandler.logger.info("Hard deleting devices")
        let deleteBefore = Date.now - 60 * 3600
        let distantFuture = Date.distantFuture
        do {
            var descriptor = FetchDescriptor<Device>(predicate: #Predicate {
                $0.deletedAt ?? distantFuture < deleteBefore
            })
            descriptor.propertiesToFetch = [\.name, \.udn, \.location]
            let models = try modelContext.fetchSafer(descriptor)

            for model in models {
                Self.logger.info("Deleteing device and apps \(model.location) with name \(model.name)")
                do {
                    try deleteAppsForDeviceUdn(udn: model.udn)
                } catch {
                    Self.logger.warning("Error deleting past apps for device \(model.udn) \(error)")
                }
                modelContext.delete(model)
            }

            try modelContext.save()
        } catch {
            Self.logger.warning("Error deleting past devices \(error)")
        }
    }

    func delete(_ id: PersistentIdentifier) async throws {
        DataHandler.logger.info("Soft deleting device \(String(describing: id))")
        if let device = modelContext.existingDevice(for: id) {
            device.deletedAt = .now
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("Error deleting device with id \(id.described())")
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
            DataHandler.logger.error("Error checking if device exists \(udn): \(error)")
        }
        return nil
    }

    private func deviceForUdn(udn: String) -> Device? {
        do {
            return try catchObjc {
                return deviceForUdnUnchecked(udn: udn)
            }
        } catch {
            Self.logger.warning("Objc error getting device \(error)")
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
            logger.info("Error getting device for id \(id.described()): \(error)")
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
            logger.info("Error getting app for id \(id.described()): \(error)")
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

extension EnvironmentValues {
  public var createDataHandler: @Sendable () async -> DataHandler? {
    get { self[DataHandlerKey.self] }
    set { self[DataHandlerKey.self] = newValue }
  }
}

public func dataHandlerCreator() -> @Sendable () async -> DataHandler {
  let container = getSharedModelContainer()
  return { DataHandler(modelContainer: container) }
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
        guard let location = (modelContext.existingDevice(for: id))?.location else {
            DataHandler.logger.error("Trying to refresh device that doeesn't exist \(String(describing: id))")
            return
        }

        guard let deviceInfo = await fetchDeviceInfo(location: location) else {
            DataHandler.logger.info("Failed to get device info \(location)")
            return
        }

        if let device = modelContext.existingDevice(for: id) {
            if device.udn.starts(with: "roam:newdevice-") {
                device.udn = deviceInfo.udn
            } else if deviceInfo.udn != device.udn {
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
            if device.name == "New device" {
                if let newName = deviceInfo.friendlyDeviceName {
                    device.name = newName
                }
            }

            try? modelContext.save()
        }

        DataHandler.logger.info("Refreshing capabilities and apps")

        var capabilities: DeviceCapabilities?
        do {
            capabilities = try await fetchDeviceCapabilities(location: location)
        } catch {
            DataHandler.logger.error("Error getting capabilities \(error)")
        }

        var apps: [AppLinkAppEntity]?
        do {
            apps = try await fetchDeviceApps(location: location)
        } catch {
            DataHandler.logger.error("Error getting device apps \(error)")
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

            if let apps {
                // Remove apps from device that aren't in fetchedApps
                var deviceApps = deviceApps.filter { app in
                    apps.contains { $0.id == app.id }
                }

                // Add new apps to device
                for app in apps where !deviceApps.contains(where: { $0.id == app.id }) {
                    let al = AppLink(id: app.id, type: app.type, name: app.name, deviceUid: device.udn)
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
            DataHandler.logger.info("Getting icon for device \(location)")
            do {
                deviceIcon = try await tryFetchDeviceIcon(location: location)
            } catch {
                DataHandler.logger.warning("Error getting device icon \(error)")
            }
        }

        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                DataHandler.logger.error("Getting device app icon for id \(appId)")
                let iconData = try await fetchAppIcon(location: location, appId: appId)
                appIcons[appId] = iconData
            } catch {
                DataHandler.logger.error("Error getting device app icon \(error)")
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
        Self.logger.info("Refreshing messages with last message \(String(describing: lastMessage?.id))")
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
                DataHandler.logger.error("Error getting latest messages \(error)")
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
            DataHandler.logger.error("Error refreshing messages \(error)")
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
    logger.info("Getting device url \(deviceUrl)")
    // Save device id and location early
    await dataHandler.updateDevice(
        modelId, name: deviceName, location: deviceUrl, udn: existingUDN
    )

    let deviceInfo = await fetchDeviceInfo(location: deviceUrl)

    // If we get a device with a different UDN, replace the device
    if let udn = deviceInfo?.udn, udn != existingUDN {
        do {
            try await dataHandler.delete(modelId)
            await dataHandler.addOrReplaceDevice(
                location: deviceUrl, friendlyDeviceName: deviceName, udn: udn
            )

        } catch {
            DataHandler.logger.error("Error saving device \(error)")
        }
        return
    }

    DataHandler.logger.info("Saving device \(deviceUrl) with id \(String(describing: modelId))")
    await dataHandler.updateDevice(
        modelId,
        name: deviceName,
        location: deviceUrl,
        udn: existingUDN
    )
    DataHandler.logger.info("Saved device \(deviceUrl)")
}
