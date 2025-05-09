import Foundation
import os.log
#if !WIDGET
import XMLCoder
#endif
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
        self.deviceImagePath = service.device.iconList.icon.first?.url
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
    }
}

private struct DeviceServiceRoot: Codable {
    let device: DeviceIconDescription

    struct DeviceIconDescription: Codable {
        let iconList: IconList
        let friendlyName: String
        let UDN: String
        let serialNumber: String

        struct IconList: Codable {
            let icon: [Icon]

            struct Icon: Codable {
                let url: String
            }
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

struct Apps: Decodable {
    let app: [AppLinkAppEntity]
}

#if !WIDGET
func fetchPreconnectionInfo(location: String) async throws -> PreconnectionDeviceInfo {
    // Fetch device details
    guard let url = URL(string: location) else {
        throw FetchDeviceIconError.badURL(location)
    }
    let (data, _) = try await URLSession.shared.data(from: url)

    // Decode XML to Root object
    let decoder = XMLDecoder()
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

    let decoder = XMLDecoder()
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
            let decoder = XMLDecoder()
            decoder.keyDecodingStrategy = .convertFromKebabCase
            return try decoder.decode(DeviceInfo.self, from: Data(xmlString.utf8))
        }
        throw APIError.badData("No valid string returned")
    } catch {
        Log.connection.error("Error getting device info: \(error, privacy: .public)")
        throw error
    }
}

func fetchDeviceApps(location: String) async throws -> [AppLinkAppEntity] {
    guard let url = URL(string: "\(location)query/apps") else {
        throw APIError.badURLError("\(location)query/apps")
    }
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLDecoder()
    let apps = try decoder.decode(Apps.self, from: data)

    return apps.app
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
