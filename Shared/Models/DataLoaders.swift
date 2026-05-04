import Foundation
import SwiftUI

// MARK: - Message List Loader
@Observable @MainActor
class MessageListLoader: RegistrationListener {
    var messages: [Message]?
    var unreadCount: Int = 0
    var isLoading: Bool = false

    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(dataHandler: RoamDataHandler) {
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(registrationToken, change: .updateMessages)
            await self.messagesUpdated(
                messages: dataHandler.requestMessages(),
                unreadCount: dataHandler.requestUnreadMessageCount()
            )
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    func messagesUpdated(messages: [Message], unreadCount: Int) {
        self.messages = messages
        self.unreadCount = unreadCount
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func deviceListUpdated(devices: [String]) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}

// MARK: - Device List Loader
@Observable @MainActor
class DeviceListLoader: RegistrationListener {
    var devices: [String]?
    var revision: Int = 0
    var isLoading: Bool = false

    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(dataHandler: RoamDataHandler) {
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(registrationToken, change: .updateDeviceList)
            await self.deviceListUpdated(devices: dataHandler.requestDeviceList())
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - RegistrationListener Implementation
    func deviceListUpdated(devices: [String]) {
        self.devices = devices
        self.revision += 1
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}

// MARK: - Hidden Device List Loader
@Observable @MainActor
class HiddenDeviceListLoader: RegistrationListener {
    var devices: [String]?
    var revision: Int = 0
    var isLoading: Bool = false

    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(dataHandler: RoamDataHandler) {
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(registrationToken, change: .updateHiddenDeviceList)
            await self.hiddenDeviceListUpdated(devices: dataHandler.requestHiddenDeviceList())
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - RegistrationListener Implementation
    func hiddenDeviceListUpdated(devices: [String]) {
        self.devices = devices
        self.revision += 1
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func deviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}

// MARK: - Device Loader
@Observable @MainActor
class DeviceLoader: RegistrationListener {
    var device: Device?
    var isLoading: Bool = false

    private let deviceId: String
    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(deviceId: String, dataHandler: RoamDataHandler) {
        self.deviceId = deviceId
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(
                registrationToken, change: .updateDevice(deviceId: deviceId))
            if let device = await dataHandler.requestDevice(id: deviceId) {
                self.deviceDetailUpdated(for: deviceId, device: device)
            }
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - Update Methods
    func setSelectedDevice() async throws {
        try await dataHandler.makePrimaryDevice(id: deviceId)
    }

    func updateDeviceName(_ name: String) async throws {
        try await dataHandler.updateDeviceName(id: deviceId, name: name)
    }

    // MARK: - RegistrationListener Implementation
    func deviceDetailUpdated(for deviceId: String, device: Device?) {
        guard deviceId == self.deviceId else {
            Log.data.error(
                "Received device update for device \(deviceId, privacy: .public) but expected \(self.deviceId, privacy: .public)"
            )
            return
        }
        self.device = device
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceListUpdated(devices: [String]) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}

// MARK: - Device Apps Loader
@Observable @MainActor
class DeviceAppsLoader: RegistrationListener {
    var apps: [AppLink]?
    var isLoading: Bool = false

    private let deviceId: String
    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(deviceId: String, dataHandler: RoamDataHandler) {
        self.deviceId = deviceId
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(
                registrationToken, change: .updateDeviceApps(deviceId: deviceId))
            await self.deviceAppsUpdated(
                for: deviceId, apps: dataHandler.requestDeviceApps(deviceId: deviceId))
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - Update Methods
    func setSelectedApp(_ appId: String) async throws {
        try await dataHandler.setSelectedApp(deviceId: deviceId, appId: appId)
    }

    // MARK: - RegistrationListener Implementation
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {
        guard deviceId == self.deviceId else { return }
        self.apps = apps
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func deviceListUpdated(devices: [String]) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
}

// MARK: - Device App Icon Loader
@Observable @MainActor
class DeviceAppIconLoader: RegistrationListener {
    var iconDataHash: String?
    var isLoading: Bool = false

    var iconData: Data? {
        guard let iconDataHash = iconDataHash else { return nil }
        // Load icon data from disk using hash
        do {
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: mainAppGroup)!
            let iconURL = containerURL.appendingPathComponent("roku-icons", isDirectory: true)
                .appendingPathComponent(iconDataHash)
            return try Data(contentsOf: iconURL)
        } catch {
            Log.data.error("Failed to load icon data for hash \(iconDataHash): \(error)")
            return nil
        }
    }

    private let deviceId: String
    private let appId: String
    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(deviceId: String, appId: String, dataHandler: RoamDataHandler) {
        self.deviceId = deviceId
        self.appId = appId
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(
                registrationToken, change: .updateAppIcon(deviceId: deviceId, appId: appId))
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - RegistrationListener Implementation
    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {
        guard deviceId == self.deviceId && appId == self.appId else { return }
        self.iconDataHash = iconDataHash
        self.isLoading = false
    }

    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func deviceListUpdated(devices: [String]) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryDeviceUpdated(device: Device?) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}

// MARK: - Primary Device Loader
@Observable @MainActor
class PrimaryDeviceLoader: RegistrationListener {
    var device: Device?
    var isLoading: Bool = false

    private let dataHandler: RoamDataHandler
    private let registrationToken: RegistrationToken

    init(dataHandler: RoamDataHandler) {
        self.dataHandler = dataHandler
        self.registrationToken = dataHandler.token()
        self.isLoading = true

        Task {
            await dataHandler.register(self.registrationToken, self)
            await dataHandler.registerForChange(registrationToken, change: .updatePrimaryDevice)
            await self.primaryDeviceUpdated(device: dataHandler.requestPrimaryDevice())
        }
    }

    deinit {
        let dataHandler = self.dataHandler
        let registrationToken = self.registrationToken
        Task {
            await dataHandler.unregister(registrationToken)
        }
    }

    // MARK: - Update Methods
    func setSelectedDevice() async throws {
        guard let device = device else { return }
        try await dataHandler.makePrimaryDevice(id: device.id)
    }

    func updateDeviceName(_ name: String) async throws {
        guard let device = device else { return }
        try await dataHandler.updateDeviceName(id: device.id, name: name)
    }

    // MARK: - RegistrationListener Implementation
    func primaryDeviceUpdated(device: Device?) {
        self.device = device
        self.isLoading = false
    }

    func appIconUpdated(for deviceId: String, appId: String, iconDataHash: String) {}
    func deviceDetailUpdated(for deviceId: String, device: Device?) {}
    func deviceListUpdated(devices: [String]) {}
    func hiddenDeviceListUpdated(devices: [String]) {}
    func primaryAppsUpdated(apps: [AppLink]?) {}
    func deviceAppsUpdated(for deviceId: String, apps: [AppLink]) {}
}
