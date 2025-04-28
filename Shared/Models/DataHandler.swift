import Foundation
import OSLog
import SwiftData
import SwiftUI

func getGlobalNewDeviceName() -> String {
    return String(localized: "New device")
}

@ModelActor
public actor DataHandler {
    static let hardDeleteTimeout: TimeInterval = 3600

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
        Log.data.notice("Updating selectedAt for app with id \(appId.described(), privacy: .public)")

        if let appLink = modelContext.existingApp(for: appId) {
            Log.data.notice("Setting appId selected to now")
            appLink.lastSelected = Date.now
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.error("Error marking app as selected \(appLink.id, privacy: .public)")
            }
        }
    }

    func setSelectedDevice(_ id: PersistentIdentifier) {
        Log.data.notice("Updating selectedAt for device with id \(String(describing: id), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            Log.data.notice("Found device to update with location \(device.location, privacy: .public)")
            device.lastSelectedAt = Date.now
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.error("Error marking device as selected \(device.location, privacy: .public)")
            }
        }
    }

    func updateDevice(_ id: PersistentIdentifier, name: String? = nil, location: String? = nil, hidden: Bool? = nil) {
        Log.data.notice("Updating device at \(id.described(), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
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
                try modelContext.saveSafer()
            } catch {
                Log.data.warning("Error updating device at location \(device.location, privacy: .public)")
            }
        }
        Log.data.notice("Updated device at \(id.described(), privacy: .public)")
    }

    @discardableResult
    func addDeviceIndistriminantly(location: String, friendlyDeviceName: String, udn: String, serial: String, hidden: Bool) -> PersistentIdentifier? {
        if let device = deviceForUdn(udn: udn) {
            device.location = location
            device.name = friendlyDeviceName
            device.hiddenAt = hidden ? Date.now : nil
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
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
                try modelContext.saveSafer()
                Log.data.notice("Added device \(String(describing: device.persistentModelID), privacy: .public)")
                return device.persistentModelID
            } catch {
                Log.data.warning("Error adding device at \(location, privacy: .public), \(error, privacy: .public)")
                return nil
            }
        }
    }

    @discardableResult
    func addOrReplaceDevice(location: String, udn: String? = nil, serial: String? = nil) async -> PersistentIdentifier? {
        if let udn, let device = deviceForUdn(udn: udn) {
            device.location = location
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
            }
            return device.persistentModelID
        }

        if let serial, let device = deviceForSerial(serial: serial) {
            device.location = location
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.warning("Error updating device fields \(error, privacy: .public)")
            }
            return device.persistentModelID
        }

        let info: PreconnectionDeviceInfo
        var foundDevice: Device?
        do {
            info = try await fetchPreconnectionInfo(location: location)
            if let device = deviceForUdn(udn: info.udn) {
                Log.data.info("Found device for udn \(info.udn, privacy: .public), updating")
                device.serial = info.serial
                device.location = location
                foundDevice = device
            } else if let device = deviceForSerial(serial: info.serial) {
                Log.data.info("Found device for serial \(info.serial, privacy: .public), updating")
                device.udn = info.udn
                device.location = location
                foundDevice = device
            }
        } catch {
            Log.data.warning("Trying to add device but no preconnection info available \(location, privacy: .public). Error: \(error, privacy: .public)")
            return nil
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
            try modelContext.saveSafer()
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
            return nil
        }
    }

    func sentToWatch(deviceId: PersistentIdentifier) {
        do {
            if let device = modelContext.existingDevice(for: deviceId) {
                device.lastSentToWatch = Date.now
                try modelContext.saveSafer()
            }
        } catch {
            Log.data.warning("Error marking device \(deviceId.described(), privacy: .public) as sent to watch \(error, privacy: .public)")
        }
    }

    func watchPossiblyDead() {
        let devices = (try? allDevices()) ?? []
        for device in devices {
            device.lastSentToWatch = nil
        }
        do {
            try modelContext.saveSafer()
        } catch {
            Log.data.warning("Error marking devices as not sent to watch \(error, privacy: .public)")
        }
    }

    func deleteInPast() async {
        Log.data.notice("Hard deleting devices")
        let deleteBefore = Date.now - Self.hardDeleteTimeout
        let distantFuture = Date.distantFuture
        do {
            var descriptor = FetchDescriptor<Device>(predicate: #Predicate {
                $0.deletedAt ?? distantFuture < deleteBefore
            })
            descriptor.propertiesToFetch = [\.name, \.udn, \.location]
            let models = try modelContext.fetchSafer(descriptor)

            for model in models {
                Log.data.notice("Deleteing device and apps \(model.location, privacy: .public) with name \(model.name, privacy: .public)")
                do {
                    try deleteAppsForDeviceUdn(udn: model.udn)
                } catch {
                    Log.data.warning("Error deleting past apps for device \(model.udn, privacy: .public) \(error, privacy: .public)")
                }
                modelContext.delete(model)
            }

            try modelContext.saveSafer()
        } catch {
            Log.data.warning("Error deleting past devices \(error, privacy: .public)")
        }
    }

    func hide(_ id: PersistentIdentifier) async throws {
        Log.data.notice("Hiding device \(String(describing: id), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            device.hiddenAt = .now
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.error("Error hiding device with id \(id.described(), privacy: .public)")
                return
            }
        }
    }

    func delete(_ id: PersistentIdentifier) async throws {
        Log.data.notice("Soft deleting device \(String(describing: id), privacy: .public)")
        if let device = modelContext.existingDevice(for: id) {
            device.deletedAt = .now
            do {
                try modelContext.saveSafer()
            } catch {
                Log.data.error("Error deleting device with id \(id.described(), privacy: .public)")
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
             \.networkType, \.powerMode,
             \.serial
        ]
        do {
            let matchingIds = try modelContext.fetchIdentifiers(matchingIds)

            if let matchingPid = matchingIds.first {
                if let device = modelContext.existingDevice(for: matchingPid) {
                    return device
                }
            }
        } catch {
            Log.data.error("Error checking if device exists \(udn, privacy: .public): \(error, privacy: .public)")
        }
        return nil
    }

    private func deviceForSerialUnchecked(serial: String) -> Device? {
        var matchingIds = FetchDescriptor<Device>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.serial == serial
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
             \.networkType, \.powerMode,
             \.serial
        ]
        do {
            let matchingIds = try modelContext.fetchIdentifiers(matchingIds)

            if let matchingPid = matchingIds.first {
                if let device = modelContext.existingDevice(for: matchingPid) {
                    return device
                }
            }
        } catch {
            Log.data.error("Error checking if device exists \(serial, privacy: .public): \(error, privacy: .public)")
        }
        return nil
    }

    private func deviceForUdn(udn: String) -> Device? {
        do {
            return try catchObjc {
                return deviceForUdnUnchecked(udn: udn)
            }
        } catch {
            Log.data.warning("Objc error getting device for udn \(error, privacy: .public)")
            return nil
        }
    }

    private func deviceForSerial(serial: String) -> Device? {
        do {
            return try catchObjc {
                return deviceForSerialUnchecked(serial: serial)
            }
        } catch {
            Log.data.warning("Objc error getting device for serial \(error, privacy: .public)")
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

        try modelContext.saveSafer()
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

    func saveSafer() throws {
        return try catchObjc {
            try self.save()
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
            Log.data.notice("Error getting device for id \(id.described(), privacy: .public): \(error, privacy: .public)")
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

protocol RefreshClient: Sendable {
    func getId() async throws -> PersistentIdentifier
    func getDeviceInfo() async throws -> DeviceInfo
    func getDeviceCapabilities() async throws -> DeviceCapabilities
    func getDeviceApps() async throws -> [AppLinkAppEntity]
    func getDeviceAppIcon(_ appId: String) async throws -> Data
    func getDeviceIcon() async throws -> Data
}

#if os(watchOS)
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
#else
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

extension DataHandler {
    func refreshDevice(client: any RefreshClient) async {
        let id: PersistentIdentifier
        do {
            id = try await client.getId()
            Log.data.notice("Refreshing device with id \(String(describing: id), privacy: .public)")
        } catch {
             Log.data.error("Failed to refresh device because couldn't get id")
            return
        }
        Log.data.notice("Refreshing device with id \(String(describing: id), privacy: .public)")

        let deviceInfo: DeviceInfo
        do {
            deviceInfo = try await client.getDeviceInfo()
            Log.data.notice("Successfully refreshed device info")
        } catch {
            Log.data.notice("Failed to get device info \(id.described(), privacy: .public), \(error, privacy: .public)")
            return
        }

        if let device = modelContext.existingDevice(for: id) {
            if deviceInfo.udn != device.udn {
                Log.data.warning("Error: trying to refresh device with udn \(deviceInfo.udn, privacy: .public), but device already has udn \(device.udn, privacy: .public)")
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
                try? modelContext.saveSafer()
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

            try? modelContext.saveSafer()
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

            try? modelContext.saveSafer()
        }

        var deviceIcon: Data?
        if deviceNeedsIcon {
            Log.data.notice("Getting icon for device")
            do {
                deviceIcon = try await client.getDeviceIcon()
            } catch {
                Log.data.warning("Error getting device icon \(error, privacy: .public)")
            }
        }

        var appIcons: [String: Data] = [:]
        for appId in appsNeedingIcons {
            do {
                Log.data.error("Getting device app icon for id \(appId, privacy: .public)")
                let iconData = try await client.getDeviceAppIcon(appId)
                Log.data.notice("Successfully refreshed device app icon")
                appIcons[appId] = iconData
            } catch {
                Log.data.error("Error getting device app icon \(error, privacy: .public)")
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
            try? modelContext.saveSafer()
        }

        await deleteInPast()
    }
}

#if !WIDGET
extension DataHandler {
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
        descriptor.propertiesToFetch = [\.id]

        var lastMessage: Message?
        do {
            lastMessage = try modelContext.fetchSafer(descriptor).last
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
        var descriptor = FetchDescriptor(
            predicate: #Predicate<Message> { model in
                model.fetchedBackend == true
            }
        )
        descriptor.propertiesToFetch = [\Message.id]
        descriptor.sortBy = [SortDescriptor(\Message.id, order: .reverse)]
        descriptor.fetchLimit = 1
        let latestMessageId = (try? modelContext.fetchSafer(descriptor))?.first?.id

        Log.data.notice("Refreshing messages with last message \(String(describing: latestMessageId), privacy: .public)")

        return await withTaskGroup(of: Int.self) { taskGroup in
            taskGroup.addTask {
                await self.trySendMessages()
                return 0
            }
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

    public func getSendableMessages() throws -> [Message] {
        Log.data.notice("Getting sendable messages")
        let tenPast = Date.now - 10
        let distantPast = Date.distantPast
        var descriptor = FetchDescriptor(
            predicate: #Predicate<Message> { model in
                model.fetchedBackend == false && (
                    (model.lastSendAttempt ?? distantPast) < tenPast
                )
            }
        )
        descriptor.propertiesToFetch = [\.id, \.message, \.unsentAttachmentData, \.lastSendAttempt]
        let foundModels = try modelContext.fetchSafer(descriptor)
        for model in foundModels {
            model.lastSendAttempt = Date.now
        }
        Log.data.notice("Got \(foundModels.count, privacy: .public) sendable messages")
        try modelContext.saveSafer()
        return foundModels
    }

    public func trySendMessages() async {
        let messages: [Message]
        do {
            messages = try self.getSendableMessages()
        } catch {
            Log.backend.notice("Error getting messages to send \(error, privacy: .public)")
            return
        }
        for message in messages {
            do {
                let messageResult = try await sendMessageDirect(message: message.message, attachment: message.unsentAttachment).get()
                message.id = messageResult.id
                message.lastSendAttempt = Date.distantFuture
                message.cycleAttachments(messageResult.attachments?.map({ a in
                    return Message.SentAttachment(id: a.id, data: a.data, filename: a.filename, mimetype: a.contentType)
                }) ?? [])
                try self.modelContext.saveSafer()
            } catch {
                Log.backend.notice("Error sending message \(message.id, privacy: .public), \(error, privacy: .public)")
                message.lastSendAttempt = nil
                try? self.modelContext.saveSafer()
            }
        }
    }

    public func sendChatMessage(message: String, attachments: [AttachmentUpload] = []) async throws {
        let firstAttachment = attachments.first
        let nonce = String(Int64.random(in: 0..<Int64.max))
        let id = generateDiscordSnowflake(Date.now.addingTimeInterval(1))
        Log.backend.info("Inserting pending message to send queue: \(message, privacy: .public)")
        self.modelContext.insert(Message(
            id: id,
            message: message,
            author: .me,
            fetchedBackend: false,
            viewed: true,
            unsentAttachment: firstAttachment,
            nonce: nonce
        ))
        try self.modelContext.saveSafer()
        Log.backend.info("Saved message to send queue: \(message, privacy: .public), id: \(id, privacy: .public)")
        await self.trySendMessages()
    }

    public func refreshExternalMessages(latestMessageId: String?, viewed: Bool) async -> Int {
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

                    let existingMessages = try modelContext.fetchSafer(existingMessageDescriptor)
                    for message in existingMessages {
                        modelContext.delete(message)
                    }
                    modelContext.insert(message)

                    message.triggerAction()
                }
                count = newMessages.count

                let savingMessages = try modelContext.fetchSafer(FetchDescriptor<Message>(
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

            try modelContext.saveSafer()

            return count
        } catch {
            Log.data.error("Error refreshing messages \(error, privacy: .public)")
            return 0
        }
    }
}
#endif
