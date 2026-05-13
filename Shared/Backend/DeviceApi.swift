import Foundation
import os.log
import Network

struct PreconnectionDeviceInfo: Codable {
    let udn: String
    let friendlyName: String
    let location: String
    let serial: String
    let deviceImagePath: String?

    fileprivate init(service: DeviceServiceRoot, location: String) {
        self.udn = service.device.UDN.stripPrefix("uuid:")
        self.friendlyName = service.device.friendlyName
        self.location = location
        self.serial = service.device.serialNumber
        self.deviceImagePath = service.device.iconList.first?.url
    }
}

struct DeviceInfo: Codable {
    let powerMode: String?
    let networkType: String?
    let ethernetMac: String?
    let wifiMac: String?
    let friendlyDeviceName: String?
    let uptime: Int?
    let udn: String
    let serialNumber: String

    let vendorName: String?
    let modelName: String?
    let modelNumber: String?
    let modelRegion: String?
    let friendlyModelName: String?
    let defaultDeviceName: String?
    let isTv: Bool?
    let isStick: Bool?
    let isPoweredByTv: Bool?
    let uiResolution: String?
    let softwareVersion: String?
    let softwareBuild: String?
    let buildNumber: String?
    let supportsEthernet: Bool?
    let supportsSuspend: Bool?
    let supportsFindRemote: Bool?
    let supportsAudioGuide: Bool?
    let supportsAirplay: Bool?
    let supportsWakeOnWlan: Bool?
    let supportsPrivateListening: Bool?
    let supportsEcsTextedit: Bool?
    let supportsEcsMicrophone: Bool?
    let supportsAudioSettings: Bool?
    let supportsRva: Bool?
    let supportsTrc: Bool?
    let headphonesConnected: Bool?
    let privateListeningBlocked: Bool?
    let hasHandsFreeVoiceRemote: Bool?
    let secureDevice: Bool?
    let developerEnabled: Bool?
    let searchEnabled: Bool?
    let voiceSearchEnabled: Bool?
    let timeZone: String?
    let country: String?
    let language: String?
    let locale: String?

    func isPowerOn() -> Bool {
        powerMode == "PowerOn"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(powerMode, forKey: .powerMode)
        try container.encodeIfPresent(networkType, forKey: .networkType)
        try container.encodeIfPresent(ethernetMac, forKey: .ethernetMac)
        try container.encodeIfPresent(wifiMac, forKey: .wifiMac)
        try container.encodeIfPresent(friendlyDeviceName, forKey: .userDeviceName)
        try container.encodeIfPresent(friendlyDeviceName, forKey: .friendlyDeviceName)
        try container.encodeIfPresent(uptime, forKey: .uptime)
        try container.encode(udn, forKey: .udn)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(vendorName, forKey: .vendorName)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encodeIfPresent(modelNumber, forKey: .modelNumber)
        try container.encodeIfPresent(modelRegion, forKey: .modelRegion)
        try container.encodeIfPresent(friendlyModelName, forKey: .friendlyModelName)
        try container.encodeIfPresent(defaultDeviceName, forKey: .defaultDeviceName)
        try container.encodeIfPresent(isTv, forKey: .isTv)
        try container.encodeIfPresent(isStick, forKey: .isStick)
        try container.encodeIfPresent(isPoweredByTv, forKey: .isPoweredByTv)
        try container.encodeIfPresent(uiResolution, forKey: .uiResolution)
        try container.encodeIfPresent(softwareVersion, forKey: .softwareVersion)
        try container.encodeIfPresent(softwareBuild, forKey: .softwareBuild)
        try container.encodeIfPresent(buildNumber, forKey: .buildNumber)
        try container.encodeIfPresent(supportsEthernet, forKey: .supportsEthernet)
        try container.encodeIfPresent(supportsSuspend, forKey: .supportsSuspend)
        try container.encodeIfPresent(supportsFindRemote, forKey: .supportsFindRemote)
        try container.encodeIfPresent(supportsAudioGuide, forKey: .supportsAudioGuide)
        try container.encodeIfPresent(supportsAirplay, forKey: .supportsAirplay)
        try container.encodeIfPresent(supportsWakeOnWlan, forKey: .supportsWakeOnWlan)
        try container.encodeIfPresent(supportsPrivateListening, forKey: .supportsPrivateListening)
        try container.encodeIfPresent(supportsEcsTextedit, forKey: .supportsEcsTextedit)
        try container.encodeIfPresent(supportsEcsMicrophone, forKey: .supportsEcsMicrophone)
        try container.encodeIfPresent(supportsAudioSettings, forKey: .supportsAudioSettings)
        try container.encodeIfPresent(supportsRva, forKey: .supportsRva)
        try container.encodeIfPresent(supportsTrc, forKey: .supportsTrc)
        try container.encodeIfPresent(headphonesConnected, forKey: .headphonesConnected)
        try container.encodeIfPresent(privateListeningBlocked, forKey: .privateListeningBlocked)
        try container.encodeIfPresent(hasHandsFreeVoiceRemote, forKey: .hasHandsFreeVoiceRemote)
        try container.encodeIfPresent(secureDevice, forKey: .secureDevice)
        try container.encodeIfPresent(developerEnabled, forKey: .developerEnabled)
        try container.encodeIfPresent(searchEnabled, forKey: .searchEnabled)
        try container.encodeIfPresent(voiceSearchEnabled, forKey: .voiceSearchEnabled)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(locale, forKey: .locale)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.powerMode = try container.decodeIfPresent(String.self, forKey: .powerMode)
        self.networkType = try container.decodeIfPresent(String.self, forKey: .networkType)
        self.ethernetMac = try container.decodeIfPresent(String.self, forKey: .ethernetMac)
        self.wifiMac = try container.decodeIfPresent(String.self, forKey: .wifiMac)
        self.friendlyDeviceName = try container.decodeIfPresent(String.self, forKey: .userDeviceName)
            ?? container.decodeIfPresent(String.self, forKey: .friendlyDeviceName)
        self.uptime = try container.decodeIfPresent(Int.self, forKey: .uptime)
        self.udn = try container.decode(String.self, forKey: .udn)
        self.serialNumber = try container.decode(String.self, forKey: .serialNumber)
        self.vendorName = try container.decodeIfPresent(String.self, forKey: .vendorName)
        self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        self.modelNumber = try container.decodeIfPresent(String.self, forKey: .modelNumber)
        self.modelRegion = try container.decodeIfPresent(String.self, forKey: .modelRegion)
        self.friendlyModelName = try container.decodeIfPresent(String.self, forKey: .friendlyModelName)
        self.defaultDeviceName = try container.decodeIfPresent(String.self, forKey: .defaultDeviceName)
        self.isTv = try Self.decodeFlexibleBool(container, .isTv)
        self.isStick = try Self.decodeFlexibleBool(container, .isStick)
        self.isPoweredByTv = try Self.decodeFlexibleBool(container, .isPoweredByTv)
        self.uiResolution = try container.decodeIfPresent(String.self, forKey: .uiResolution)
        self.softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
        self.softwareBuild = try container.decodeIfPresent(String.self, forKey: .softwareBuild)
        self.buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        self.supportsEthernet = try Self.decodeFlexibleBool(container, .supportsEthernet)
        self.supportsSuspend = try Self.decodeFlexibleBool(container, .supportsSuspend)
        self.supportsFindRemote = try Self.decodeFlexibleBool(container, .supportsFindRemote)
        self.supportsAudioGuide = try Self.decodeFlexibleBool(container, .supportsAudioGuide)
        self.supportsAirplay = try Self.decodeFlexibleBool(container, .supportsAirplay)
        self.supportsWakeOnWlan = try Self.decodeFlexibleBool(container, .supportsWakeOnWlan)
        self.supportsPrivateListening = try Self.decodeFlexibleBool(container, .supportsPrivateListening)
        self.supportsEcsTextedit = try Self.decodeFlexibleBool(container, .supportsEcsTextedit)
        self.supportsEcsMicrophone = try Self.decodeFlexibleBool(container, .supportsEcsMicrophone)
        self.supportsAudioSettings = try Self.decodeFlexibleBool(container, .supportsAudioSettings)
        self.supportsRva = try Self.decodeFlexibleBool(container, .supportsRva)
        self.supportsTrc = try Self.decodeFlexibleBool(container, .supportsTrc)
        self.headphonesConnected = try Self.decodeFlexibleBool(container, .headphonesConnected)
        self.privateListeningBlocked = try Self.decodeFlexibleBool(container, .privateListeningBlocked)
        self.hasHandsFreeVoiceRemote = try Self.decodeFlexibleBool(container, .hasHandsFreeVoiceRemote)
        self.secureDevice = try Self.decodeFlexibleBool(container, .secureDevice)
        self.developerEnabled = try Self.decodeFlexibleBool(container, .developerEnabled)
        self.searchEnabled = try Self.decodeFlexibleBool(container, .searchEnabled)
        self.voiceSearchEnabled = try Self.decodeFlexibleBool(container, .voiceSearchEnabled)
        self.timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.locale = try container.decodeIfPresent(String.self, forKey: .locale)
    }

    // Roku XML serializes booleans as "true"/"false" text. XMLStreamDecoder
    // doesn't natively coerce those into Bool, so accept either form.
    private static func decodeFlexibleBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Bool? {
        if let bool = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return bool
        }
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        switch raw.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    enum CodingKeys: CodingKey {
        case powerMode
        case networkType
        case ethernetMac
        case wifiMac
        case friendlyDeviceName
        case userDeviceName
        case uptime
        case udn
        case serialNumber
        case vendorName
        case modelName
        case modelNumber
        case modelRegion
        case friendlyModelName
        case defaultDeviceName
        case isTv
        case isStick
        case isPoweredByTv
        case uiResolution
        case softwareVersion
        case softwareBuild
        case buildNumber
        case supportsEthernet
        case supportsSuspend
        case supportsFindRemote
        case supportsAudioGuide
        case supportsAirplay
        case supportsWakeOnWlan
        case supportsPrivateListening
        case supportsEcsTextedit
        case supportsEcsMicrophone
        case supportsAudioSettings
        case supportsRva
        case supportsTrc
        case headphonesConnected
        case privateListeningBlocked
        case hasHandsFreeVoiceRemote
        case secureDevice
        case developerEnabled
        case searchEnabled
        case voiceSearchEnabled
        case timeZone
        case country
        case language
        case locale
    }
}

private struct DeviceServiceRoot: Codable {
    let device: DeviceIconDescription

    struct DeviceIconDescription: Codable {
        let iconList: [Icon]
        let friendlyName: String
        let UDN: String
        let serialNumber: String

        struct Icon: Codable {
            let url: String
        }
    }
}

enum FetchDeviceIconError: Error, LocalizedError {
    case badURL(String)
    case badIconURL(String)
    case noIconsListed
}

struct AudioDevice: Codable {
    let capabilities: Capabilities
    let globalInfo: GlobalInfo
    let rtpInfo: RtpInfo?

    enum CodingKeys: String, CodingKey {
        case capabilities
        case rtpInfo = "rtp-info"
        case globalInfo = "global"
    }

    struct GlobalInfo: Codable {
        let muted: Bool
        let volume: UInt8
        let destinationList: String?

        enum CodingKeys: String, CodingKey {
            case muted
            case volume
            case destinationList = "destination-list"
        }
    }

    struct Capabilities: Codable {
        let allDestinations: String?

        enum CodingKeys: String, CodingKey {
            case allDestinations = "all-destinations"
        }
    }

    struct RtpInfo: Codable {
        let rtcpPort: UInt16?

        enum CodingKeys: String, CodingKey {
            case rtcpPort = "rtcp-port"
        }
    }
}

struct DeviceCapabilities {
    let supportsDatagram: Bool
    let rtcpPort: UInt16?
}

typealias Apps = [ AppLink]

#if !WIDGET
func fetchPreconnectionInfo(location: String) async throws -> PreconnectionDeviceInfo {
    // Fetch device details
    guard let url = URL(string: location) else {
        throw FetchDeviceIconError.badURL(location)
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 8

    let (data, _) = try await URLSession.shared.data(for: request)

    // Decode XML to Root object
    let decoder = XMLStreamDecoder()
    let root = try decoder.decode(DeviceServiceRoot.self, from: data)

    return PreconnectionDeviceInfo(service: root, location: location)
}
#endif

func fetchDeviceIcon(info: PreconnectionDeviceInfo) async throws -> Data {
    let location = info.location
    if let iconURL = info.deviceImagePath {
        guard let fullIconURL = URL(string: "\(location)\(iconURL)") else {
            throw FetchDeviceIconError.badIconURL("\(location)\(iconURL)")
        }
        return try await fetchURLIcon(url: fullIconURL)
    } else {
        throw FetchDeviceIconError.noIconsListed
    }
}

#if os(watchOS) && !WIDGET
func fetchDeviceCapabilities(location: String) async throws -> DeviceCapabilities {
    let url = URL(string: "\(location)query/audio-device")!
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLStreamDecoder()
    let audioDevice = try decoder.decode(AudioDevice.self, from: data)

    let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
    let rtcpPort = audioDevice.rtpInfo?.rtcpPort

    return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
}

func fetchDeviceInfo(location: String) async throws -> DeviceInfo {
    let deviceInfoURL = "\(location)query/device-info"
    guard let url = URL(string: deviceInfoURL) else {
        Log.connection.error("Unable to get device info due to bad url \(deviceInfoURL, privacy: .public)")
        throw APIError.badURLError(location)
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 1.5
    request.httpMethod = "GET"

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        if let xmlString = String(data: data, encoding: .utf8) {
            let decoder = XMLStreamDecoder(.convertFromKebabCase)
            return try decoder.decode(DeviceInfo.self, from: Data(xmlString.utf8))
        }
        throw APIError.badData("No valid string returned")
    } catch {
        Log.connection.error("Error getting device info: \(error, privacy: .public)")
        throw error
    }
}

func fetchDeviceApps(location: String) async throws -> [ AppLink] {
    guard let url = URL(string: "\(location)query/apps") else {
        throw APIError.badURLError("\(location)query/apps")
    }
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLStreamDecoder()
    let apps = try decoder.decode(Apps.self, from: data)

    return apps
}

func fetchAppIcon(location: String, appId: String) async throws -> Data {
    guard let url = URL(string: "\(location)query/icon/\(appId)") else {
        throw APIError.badURLError("\(location)query/icon/\(appId)")
    }
    return try await fetchURLIcon(url: url)
}
#endif

func fetchURLIcon(url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let mimeType = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String else {
        throw APIError.missingHeader("Content-Type")
    }

    return try await decodeImage(data: data, mimeType: mimeType)
}
