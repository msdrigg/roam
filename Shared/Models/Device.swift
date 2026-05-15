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

    // Explicit Equatable — broken into independent guard statements rather
    // than a flat `&&` chain. The synthesized version was 130-176ms; a flat
    // chain of 38 comparisons was 505ms; per-statement guards type-check
    // each comparison independently.
    public static func == (lhs: Device, rhs: Device) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.location == rhs.location else { return false }
        guard lhs.udn == rhs.udn else { return false }
        guard lhs.serial == rhs.serial else { return false }
        guard lhs.lastSentToWatch == rhs.lastSentToWatch else { return false }
        guard lhs.lastSelectedAt == rhs.lastSelectedAt else { return false }
        guard lhs.lastSyncAt == rhs.lastSyncAt else { return false }
        guard lhs.lastOnlineAt == rhs.lastOnlineAt else { return false }
        guard lhs.lastScannedAt == rhs.lastScannedAt else { return false }
        guard lhs.hiddenAt == rhs.hiddenAt else { return false }
        guard lhs.powerMode == rhs.powerMode else { return false }
        guard lhs.networkType == rhs.networkType else { return false }
        guard lhs.wifiMAC == rhs.wifiMAC else { return false }
        guard lhs.ethernetMAC == rhs.ethernetMAC else { return false }
        guard lhs.rtcpPort == rhs.rtcpPort else { return false }
        guard lhs.supportsDatagram == rhs.supportsDatagram else { return false }
        guard lhs.iconHash == rhs.iconHash else { return false }
        guard lhs.vendorName == rhs.vendorName else { return false }
        guard lhs.modelName == rhs.modelName else { return false }
        guard lhs.modelNumber == rhs.modelNumber else { return false }
        guard lhs.modelRegion == rhs.modelRegion else { return false }
        guard lhs.friendlyModelName == rhs.friendlyModelName else { return false }
        guard lhs.isTV == rhs.isTV else { return false }
        guard lhs.isStick == rhs.isStick else { return false }
        guard lhs.isPoweredByTV == rhs.isPoweredByTV else { return false }
        guard lhs.uiResolution == rhs.uiResolution else { return false }
        guard lhs.softwareVersion == rhs.softwareVersion else { return false }
        guard lhs.buildNumber == rhs.buildNumber else { return false }
        guard lhs.supportsAudioSettings == rhs.supportsAudioSettings else { return false }
        guard lhs.supportsPrivateListening == rhs.supportsPrivateListening else { return false }
        guard lhs.supportsFindRemote == rhs.supportsFindRemote else { return false }
        guard lhs.supportsSuspend == rhs.supportsSuspend else { return false }
        guard lhs.supportsAirplay == rhs.supportsAirplay else { return false }
        guard lhs.supportsEthernet == rhs.supportsEthernet else { return false }
        guard lhs.supportsWakeOnWlan == rhs.supportsWakeOnWlan else { return false }
        guard lhs.headphonesConnected == rhs.headphonesConnected else { return false }
        guard lhs.country == rhs.country else { return false }
        guard lhs.timeZone == rhs.timeZone else { return false }
        return true
    }
}

#if !os(watchOS)
import CoreSpotlight

extension Device: IndexedEntity {}
#endif
