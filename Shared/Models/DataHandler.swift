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
}

// MARK: - Main Data Handler
actor RoamDataHandler {
    private let fileHandler: FileDataHandler
    private var updateListeners: [RegistrationToken: RegistrationListenerRef] = [:]
    private var updateRegistrations: [ChangeOperation: Set<RegistrationToken>] = [:]

    // Cache storage
    private var cachedDeviceData: [String: Device] = [:]
    private var cachedDeviceApps: [String: [AppLink]] = [:]
    private var cachedDeviceList: [String]?
    private var cachedHiddenDeviceList: [String]?
    private var cachedPrimaryDevice: Device?
    private var cachedPrimaryApps: [AppLink]?

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

    private init(rootPath: String) {
        self.fileHandler = FileDataHandler(rootPath: rootPath)
        Task {
            await self.preloadDeviceList()
            await self.preloadPrimaryDevice()
            await self.preloadPrimaryApps()
        }
    }

    private static func getForShared() -> Self? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
            Log.backend.error("Failed to get app group container URL")
            return nil
        }
        print("Getting container url \(containerURL)")
        return self.init(rootPath: containerURL.appendingPathComponent("rootData").path(percentEncoded: false))
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
        // TODO:
        // Icon loading implementation would go here
        // This would check for cached icon hash and notify if available
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
    func addDevice(location: String, friendlyDeviceName: String, udn: String, serial: String, hidden: Bool = false) throws -> String {
        let device = Device(
            name: friendlyDeviceName,
            location: location,
            udn: udn,
            serial: serial,
            hiddenAt: hidden ? Date.now : nil,
        )

        try saveDeviceToDisk(device)
        cachedDeviceData[device.id] = device

        // Update lists
        try updateDeviceListsAfterSave(device)

        self.notifyDeviceUpdated(deviceId: device.id, device: device)

        return device.id
    }

    func setDeviceHidden(id: String, hidden: Bool) throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.hiddenAt = hidden ? Date.now : nil

        try saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        try updateDeviceListsAfterSave(device)

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func updateDeviceLocation(id: String, location: String) throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.location = location

        try saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func updateDeviceName(id: String, name: String) throws {
        guard var device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        device.name = name

        try saveDeviceToDisk(device)
        cachedDeviceData[id] = device

        self.notifyDeviceUpdated(deviceId: id, device: device)
    }

    func setSelectedApp(deviceId: String, appId: String) throws {
        Log.data.info("App selected \(appId, privacy: .public) for device \(deviceId, privacy: .public)")
    }

    func deleteDevice(id: String) throws {
        guard let device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        if device.id == self.requestPrimaryDevice()?.id {
            if let newDeviceId = self.requestDeviceList().first {
                try self.makePrimaryDevice(id: newDeviceId)
            }
        }

        try deleteDeviceOnDisk(id)
        cachedDeviceData[id] = nil // Remove from cache since it's deleted

        try updateDeviceListsAfterDelete(udn: id)

        self.notifyDeviceUpdated(deviceId: id, device: nil)
    }

    func setDeviceApps(deviceId: String, apps: [AppLink]) throws {
        try saveDeviceAppsToDisk(deviceId: deviceId, apps: apps)
        cachedDeviceApps[deviceId] = apps

        // Update primary apps cache if this is primary device
        if cachedPrimaryDevice?.id == deviceId {
            cachedPrimaryApps = apps
            self.notifyPrimaryAppsUpdated(apps: apps)
        }

        self.notifyDeviceAppsUpdated(deviceId: deviceId, apps: apps)
    }

    func setDeviceDetails(device: Device) throws {
        try saveDeviceToDisk(device)
        cachedDeviceData[device.id] = device

        try updateDeviceListsAfterSave(device)

        // Update primary device cache if this is primary device
        if cachedPrimaryDevice?.id == device.id {
            cachedPrimaryDevice = device
            self.notifyPrimaryDeviceUpdated(device: device)
        }

        self.notifyDeviceUpdated(deviceId: device.id, device: device)
    }

    func makePrimaryDevice(id: String) throws {
        guard let device = try cachedDeviceData[id] ?? loadDeviceFromDisk(id: id) else {
            throw DataHandlerError.deviceNotFound
        }

        // Update device's lastSelectedAt
        var updatedDevice = device
        updatedDevice.lastSelectedAt = Date.now
        try saveDeviceToDisk(updatedDevice)
        cachedDeviceData[id] = updatedDevice

        // Create symlinks
        try fileHandler.createSymlink(from: "primaryDevice.bin", to: "\(id).bin")
        try? fileHandler.createSymlink(from: "primaryDevice.apps.bin", to: "\(id).apps.bin")

        // Update device order in lists
        try updateDeviceOrderAfterSelection(selectedUdn: id)

        // Update caches
        cachedPrimaryDevice = updatedDevice
        cachedPrimaryApps = cachedDeviceApps[id] ?? (try? loadDeviceAppsFromDisk(deviceId: id))

        self.notifyPrimaryDeviceUpdated(device: updatedDevice)
        if let apps = self.cachedPrimaryApps {
            self.notifyPrimaryAppsUpdated(apps: apps)
        }
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

    // MARK: - Private Disk Operations
    private func loadDeviceListFromDisk() throws -> [String] {
        guard fileHandler.fileExists("devices.bin") else { return [] }
        let deviceList = try fileHandler.loadJSON("devices.bin", as: DeviceListData.self)
        return deviceList.devices
    }

    private func loadHiddenDeviceListFromDisk() throws -> [String] {
        guard fileHandler.fileExists("hiddenDevices.bin") else { return [] }
        let deviceList = try fileHandler.loadJSON("hiddenDevices.bin", as: DeviceListData.self)
        return deviceList.devices
    }

    private func loadDeviceFromDisk(id: String) throws -> Device? {
        let filename = "\(id).bin"
        guard fileHandler.fileExists(filename) else { return nil }
        return try fileHandler.loadJSON(filename, as: Device.self)
    }

    private func loadDeviceAppsFromDisk(deviceId: String) throws -> [AppLink] {
        let filename = "\(deviceId).apps.bin"
        guard fileHandler.fileExists(filename) else { return [] }
        return try fileHandler.loadJSON(filename, as: [AppLink].self)
    }

    private func loadPrimaryDeviceFromDisk() throws -> Device? {
        guard fileHandler.fileExists("primaryDevice.bin") else { return nil }
        return try fileHandler.loadJSON("primaryDevice.bin", as: Device.self)
    }

    private func loadPrimaryAppsFromDisk() throws -> [AppLink]? {
        guard fileHandler.fileExists("primaryDevice.apps.bin") else { return [] }
        return try fileHandler.loadJSON("primaryDevice.apps.bin", as: [AppLink].self)
    }

    private func saveDeviceToDisk(_ device: Device) throws {
        try fileHandler.saveJSON(device, to: "\(device.id).bin")
        if let serial = device.serial {
            try fileHandler.createSymlink(from: "serial.\(serial).bin", to: "\(device.id).bin")
        }
    }

    private func deleteDeviceOnDisk(_ deviceId: String) throws {
        try fileHandler.deleteFile("\(deviceId).bin")
        try fileHandler.deleteFile("\(deviceId).apps.bin")
    }

    private func saveDeviceAppsToDisk(deviceId: String, apps: [AppLink]) throws {
        try fileHandler.saveJSON(apps, to: "\(deviceId).apps.bin")
        if deviceId == requestPrimaryDevice()?.id {
            try? fileHandler.createSymlink(from: "primaryDevice.apps.bin", to: "\(deviceId).apps.bin")
        }
    }

    private func saveDeviceListToDisk(_ devices: [String]) throws {
        try fileHandler.saveJSON(DeviceListData(devices: devices), to: "devices.bin")
    }

    private func saveHiddenDeviceListToDisk(_ devices: [String]) throws {
        try fileHandler.saveJSON(DeviceListData(devices: devices), to: "hiddenDevices.bin")
    }

    // MARK: - Private Helper Methods
    private func updateDeviceListsAfterSave(_ device: Device) throws {
        let isHidden = device.hiddenAt != nil

        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()
        var hiddenDevices = try cachedHiddenDeviceList ?? loadHiddenDeviceListFromDisk()

        let hasNewPrimary = devices.isEmpty

        // Remove from both lists first
        devices.removeAll { $0 == device.id }
        hiddenDevices.removeAll { $0 == device.id }

        // Add to appropriate list
        if isHidden {
            hiddenDevices.append(device.id)
        } else {
            devices.append(device.id)
        }

        // Save and update cache
        try saveDeviceListToDisk(devices)
        try saveHiddenDeviceListToDisk(hiddenDevices)

        cachedDeviceList = devices
        cachedHiddenDeviceList = hiddenDevices

        if hasNewPrimary {
            try self.makePrimaryDevice(id: device.id)
        }

        self.notifyDeviceListUpdated(devices: devices)
        self.notifyHiddenDeviceListUpdated(devices: hiddenDevices)
    }

    private func updateDeviceListsAfterDelete(udn: String) throws {
        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()
        var hiddenDevices = try cachedHiddenDeviceList ?? loadHiddenDeviceListFromDisk()

        devices.removeAll { $0 == udn }
        hiddenDevices.removeAll { $0 == udn }

        try saveDeviceListToDisk(devices)
        try saveHiddenDeviceListToDisk(hiddenDevices)

        cachedDeviceList = devices
        cachedHiddenDeviceList = hiddenDevices

        self.notifyDeviceListUpdated(devices: devices)
        self.notifyHiddenDeviceListUpdated(devices: hiddenDevices)
    }

    private func updateDeviceOrderAfterSelection(selectedUdn: String) throws {
        var devices = try cachedDeviceList ?? loadDeviceListFromDisk()

        // Move selected device to front
        devices.removeAll { $0 == selectedUdn }
        devices.insert(selectedUdn, at: 0)

        try saveDeviceListToDisk(devices)
        cachedDeviceList = devices

        self.notifyDeviceListUpdated(devices: devices)
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

    // MARK: - Device Management Extension
#if !WIDGET
    func requestDeviceForSerial(serial: String) async -> Device? {
        // First check all cached devices for matching serial
        for cachedDevice in cachedDeviceData.values where cachedDevice.serial == serial {
            return cachedDevice
        }

        // If not found in cache, try to load from serial.{serial}.bin file
        let serialFilename = "serial.\(serial).bin"
        guard fileHandler.fileExists(serialFilename) else {
            return nil
        }

        do {
            let device = try fileHandler.loadJSON(serialFilename, as: Device.self)
            // Cache the device
            cachedDeviceData[device.id] = device
            return device
        } catch {
            Log.data.error("Failed to load device for serial \(serial, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func addOrReplaceDevice(location: String, id: String? = nil, serial: String? = nil) async throws -> String {
        // Check if device exists by UDN
        if let id, let device = self.requestDevice(id: id) {
            var updatedDevice = device
            updatedDevice.location = location
            do {
                try self.setDeviceDetails(device: updatedDevice)
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
                try self.setDeviceDetails(device: updatedDevice)
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
            try self.setDeviceDetails(device: device)
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
                try self.setDeviceDetails(device: device)
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
                    try self.setDeviceDetails(device: device)
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
            try self.setDeviceDetails(device: device)
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

        if var fetchedApps = fetchedApps {
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
            try self.setDeviceDetails(device: device)
            if let earlyUpdatedApps {
                try self.setDeviceApps(deviceId: deviceId, apps: earlyUpdatedApps)
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
                try self.setDeviceDetails(device: device)
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

                    // Notify that app icon was updated
                    Task {
                        // TODO: How to notify for app icon updated
//                        await self.appIconUpdated(for: deviceId, appId: appId, iconDataHash: iconHash)
                    }

                    Log.data.notice("Stored app icon for \(appId)")
                } catch {
                    Log.data.error("Error storing app icon for \(appId): \(error, privacy: .public)")
                }
            }

            // Save updated apps with icon hashes
            if !appsToUpdate.isEmpty {
                do {
                    try self.setDeviceApps(deviceId: deviceId, apps: afterUpdateApps)
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
    func initialize() {
        if loadTestingData() {
            // swiftlint:disable:next force_try
            try! self.loadTestData()
        } else if usingTestingData() {
            // swiftlint:disable:next force_try
            try! self.clearData()
        }
    }

    private func loadTestData() throws {
        // Clear existing data first
        try clearData()

        #if DEBUG
        // Load test devices
        let testDevices = getTestingDevices()
        var deviceIds: [String] = []

        for device in testDevices {
            try saveDeviceToDisk(device)
            cachedDeviceData[device.id] = device
            deviceIds.append(device.id)

            // Load apps for this device
            let testApps = getTestingAppLinks(deviceId: device.udn)
            try saveDeviceAppsToDisk(deviceId: device.id, apps: testApps)
            cachedDeviceApps[device.id] = testApps
        }

        // Save device lists
        try saveDeviceListToDisk(deviceIds)
        cachedDeviceList = deviceIds

        // Initialize empty hidden device list
        cachedHiddenDeviceList = []
        try saveHiddenDeviceListToDisk([])

        // Set first device as primary if available
        if let firstDevice = testDevices.first {
            try self.makePrimaryDevice(id: firstDevice.id)
        }

        // Load test messages
        let testMessages = getTestingMessages()
        // TODO: Implement message saving when message system is complete
        // For now, messages will be handled separately

        Log.data.info("Loaded test data: \(testDevices.count) devices, \(testDevices.map { cachedDeviceApps[$0.id]?.count ?? 0 }.reduce(0, +)) total apps, \(testMessages.count) messages")
        #endif
    }

    private func clearData() throws {
        // Clear all caches
        cachedDeviceData.removeAll()
        cachedDeviceApps.removeAll()
        cachedDeviceList = nil
        cachedHiddenDeviceList = nil
        cachedPrimaryDevice = nil
        cachedPrimaryApps = nil

        // Delete all files in the root directory
        try fileHandler.clearAllFiles()

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
