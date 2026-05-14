import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct Device: AppEntity, Equatable, Identifiable, Hashable, Codable {
    public var name: String
    public var location: String
    public var udn: String
    public var serial: String?
    public var lastSentToWatch: Date?

    public var lastSelectedAt: Date?
    public var lastSyncAt: Date?
    public var lastOnlineAt: Date?
    public var lastScannedAt: Date?
    public var hiddenAt: Date?

    // DisplayOff or PowerOn or Suspend
    public var powerMode: String?
    public var networkType: String?
    public var wifiMAC: String?
    public var ethernetMAC: String?

    public var rtcpPort: UInt16?
    public var supportsDatagram: Bool?
    public var iconHash: String?

    public var vendorName: String?
    public var modelName: String?
    public var modelNumber: String?
    public var modelRegion: String?
    public var friendlyModelName: String?
    public var isTV: Bool?
    public var isStick: Bool?
    public var isPoweredByTV: Bool?
    public var uiResolution: String?
    public var softwareVersion: String?
    public var buildNumber: String?
    public var supportsAudioSettings: Bool?
    public var supportsPrivateListening: Bool?
    public var supportsFindRemote: Bool?
    public var supportsSuspend: Bool?
    public var supportsAirplay: Bool?
    public var supportsEthernet: Bool?
    public var supportsWakeOnWlan: Bool?
    public var headphonesConnected: Bool?
    public var country: String?
    public var timeZone: String?

    public var id: String {
        udn
    }
    init(
        name: String, location: String, udn: String,
        serial: String? = nil, lastSentToWatch: Date? = nil,
        lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil,
        lastScannedAt: Date? = nil, hiddenAt: Date? = nil,
        powerMode: String? = nil, networkType: String? = nil,
        wifiMAC: String? = nil, ethernetMAC: String? = nil,
        rtcpPort: UInt16? = nil, supportsDatagram: Bool? = nil,
        iconHash: String? = nil,
        vendorName: String? = nil, modelName: String? = nil,
        modelNumber: String? = nil, modelRegion: String? = nil,
        friendlyModelName: String? = nil,
        isTV: Bool? = nil, isStick: Bool? = nil, isPoweredByTV: Bool? = nil,
        uiResolution: String? = nil, softwareVersion: String? = nil,
        buildNumber: String? = nil,
        supportsAudioSettings: Bool? = nil,
        supportsPrivateListening: Bool? = nil,
        supportsFindRemote: Bool? = nil, supportsSuspend: Bool? = nil,
        supportsAirplay: Bool? = nil, supportsEthernet: Bool? = nil,
        supportsWakeOnWlan: Bool? = nil,
        headphonesConnected: Bool? = nil,
        country: String? = nil, timeZone: String? = nil
    ) {
        self.serial = serial
        self.name = name
        self.location = location
        self.udn = udn
        self.lastSentToWatch = lastSentToWatch
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.lastScannedAt = lastScannedAt
        self.hiddenAt = hiddenAt
        self.powerMode = powerMode
        self.networkType = networkType
        self.wifiMAC = wifiMAC
        self.ethernetMAC = ethernetMAC
        self.rtcpPort = rtcpPort
        self.supportsDatagram = supportsDatagram
        self.iconHash = iconHash
        self.vendorName = vendorName
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.modelRegion = modelRegion
        self.friendlyModelName = friendlyModelName
        self.isTV = isTV
        self.isStick = isStick
        self.isPoweredByTV = isPoweredByTV
        self.uiResolution = uiResolution
        self.softwareVersion = softwareVersion
        self.buildNumber = buildNumber
        self.supportsAudioSettings = supportsAudioSettings
        self.supportsPrivateListening = supportsPrivateListening
        self.supportsFindRemote = supportsFindRemote
        self.supportsSuspend = supportsSuspend
        self.supportsAirplay = supportsAirplay
        self.supportsEthernet = supportsEthernet
        self.supportsWakeOnWlan = supportsWakeOnWlan
        self.headphonesConnected = headphonesConnected
        self.country = country
        self.timeZone = timeZone
    }

    public var iconURL: URL? {
        guard let iconHash else { return nil }

        // Get the group container directory
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
            Log.data.error("Unable to get group container URL")
            return nil
        }

        return containerURL
            .appendingPathComponent("roku-icons", isDirectory: true)
            .appendingPathComponent(iconHash)
    }

    func powerModeOn() -> Bool {
        powerMode == "PowerOn"
    }

    var visible: Bool {
        return self.hiddenAt == nil
    }

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Device", comment: "TV Device Selection Option"))

    public struct DeviceQuery: EntityQuery {
        public init() {}

        public func entities(for identifiers: [Device.ID]) async throws -> [Device] {
            let dataHandler = try await RoamDataHandler.sharedChecked()
            let deviceIds = await dataHandler.requestDeviceList().filter { id in
                identifiers.contains(id)
            }
            return await dataHandler.requestAllDevices(deviceIds)
        }

        public func entities(matching string: String) async throws -> [Device] {
            let dataHandler = try await RoamDataHandler.sharedChecked()
            let deviceIds = await dataHandler.requestDeviceList()
            let devices = await dataHandler.requestAllDevices(deviceIds)
            return devices.filter { d in
                d.name ~= string
            }
        }

        public func suggestedEntities() async throws -> [Device] {
            let dataHandler = try await RoamDataHandler.sharedChecked()
            let deviceIds = await dataHandler.requestDeviceList()
            let devices = await dataHandler.requestAllDevices(deviceIds)
            return devices.sorted { a, b in
                a.lastSelectedAt ?? Date.distantPast < b.lastSelectedAt ?? Date.distantPast
            }
        }
    }

    public static let defaultQuery = DeviceQuery()

    public var displayRepresentation: DisplayRepresentation {
        if let iconURL {
            DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(url: iconURL))
        } else {
            DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: "app.dashed"))
        }
    }

    func macs() -> [String] {
        return [self.ethernetMAC, self.wifiMAC].compactMap({$0})
    }

    var displayHash: String {
        "\(name)-\(udn)-\(isOnline())-\(location)-\(String(describing: supportsDatagram))-\(id)"
    }

    func isOnline() -> Bool {
        guard let lastOnlineAt else {
            return false
        }
        return Date().timeIntervalSince(lastOnlineAt) < 60
    }

    // Explicit Equatable — the synthesized version takes 130-176ms to
    // type-check across all three targets because of the field count.
    public static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.name == rhs.name
            && lhs.location == rhs.location
            && lhs.udn == rhs.udn
            && lhs.serial == rhs.serial
            && lhs.lastSentToWatch == rhs.lastSentToWatch
            && lhs.lastSelectedAt == rhs.lastSelectedAt
            && lhs.lastSyncAt == rhs.lastSyncAt
            && lhs.lastOnlineAt == rhs.lastOnlineAt
            && lhs.lastScannedAt == rhs.lastScannedAt
            && lhs.hiddenAt == rhs.hiddenAt
            && lhs.powerMode == rhs.powerMode
            && lhs.networkType == rhs.networkType
            && lhs.wifiMAC == rhs.wifiMAC
            && lhs.ethernetMAC == rhs.ethernetMAC
            && lhs.rtcpPort == rhs.rtcpPort
            && lhs.supportsDatagram == rhs.supportsDatagram
            && lhs.iconHash == rhs.iconHash
            && lhs.vendorName == rhs.vendorName
            && lhs.modelName == rhs.modelName
            && lhs.modelNumber == rhs.modelNumber
            && lhs.modelRegion == rhs.modelRegion
            && lhs.friendlyModelName == rhs.friendlyModelName
            && lhs.isTV == rhs.isTV
            && lhs.isStick == rhs.isStick
            && lhs.isPoweredByTV == rhs.isPoweredByTV
            && lhs.uiResolution == rhs.uiResolution
            && lhs.softwareVersion == rhs.softwareVersion
            && lhs.buildNumber == rhs.buildNumber
            && lhs.supportsAudioSettings == rhs.supportsAudioSettings
            && lhs.supportsPrivateListening == rhs.supportsPrivateListening
            && lhs.supportsFindRemote == rhs.supportsFindRemote
            && lhs.supportsSuspend == rhs.supportsSuspend
            && lhs.supportsAirplay == rhs.supportsAirplay
            && lhs.supportsEthernet == rhs.supportsEthernet
            && lhs.supportsWakeOnWlan == rhs.supportsWakeOnWlan
            && lhs.headphonesConnected == rhs.headphonesConnected
            && lhs.country == rhs.country
            && lhs.timeZone == rhs.timeZone
    }
}

#if !os(watchOS)
import CoreSpotlight

extension Device: IndexedEntity {}
#endif
