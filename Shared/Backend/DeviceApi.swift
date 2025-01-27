import Foundation
import os.log
import XMLCoder
import Network

struct DeviceInfo: Codable {
    let powerMode: String?
    let networkType: String?
    let ethernetMac: String?
    let wifiMac: String?
    let friendlyDeviceName: String?
    let uptime: Int?
    let udn: String

    func isPowerOn() -> Bool {
        powerMode == "PowerOn"
    }
}

struct Root: Codable {
    let device: DeviceIconDescription
}

struct DeviceIconDescription: Codable {
    let iconList: IconList
}

struct IconList: Codable {
    let icon: [Icon]
}

struct Icon: Codable {
    let url: String
}

enum FetchDeviceIconError: Swift.Error, LocalizedError {
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

struct DeviceCapabilities {
    let supportsDatagram: Bool
    let rtcpPort: UInt16?
}

struct Apps: Decodable {
    let app: [AppLinkAppEntity]
}

private let logger = Logger(
    subsystem: getLogSubsystem(),
    category: "FetchDevice"
)

func fetchDeviceIcon(location: String) async throws -> Data {
    // Fetch device details
    guard let url = URL(string: location) else {
        throw FetchDeviceIconError.badURL(location)
    }
    let (data, _) = try await URLSession.shared.data(from: url)

    // Decode XML to Root object
    let decoder = XMLDecoder()
    let root = try decoder.decode(Root.self, from: data)

    // Fetch device icon data
    if let iconURL = root.device.iconList.icon.first?.url {
        guard let fullIconURL = URL(string: "\(location)\(iconURL)") else {
            throw FetchDeviceIconError.badIconURL("\(location)\(iconURL)")
        }
        return try await fetchURLIcon(url: fullIconURL)

    } else {
        throw FetchDeviceIconError.noIconsListed
    }
}

#if os(watchOS)
func fetchDeviceCapabilities(location: String) async throws -> DeviceCapabilities {
    let url = URL(string: "\(location)query/audio-device")!
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLDecoder()
    let audioDevice = try decoder.decode(AudioDevice.self, from: data)

    let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
    let rtcpPort = audioDevice.rtpInfo?.rtcpPort

    return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
}

func fetchDeviceInfo(location: String) async -> DeviceInfo? {
    let deviceInfoURL = "\(location)query/device-info"
    guard let url = URL(string: deviceInfoURL) else {
        logger.error("Unable to get device info due to bad url \(deviceInfoURL, privacy: .public)")
        return nil
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 1.5
    request.httpMethod = "GET"

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        if let xmlString = String(data: data, encoding: .utf8) {
            let decoder = XMLDecoder()
            decoder.keyDecodingStrategy = .convertFromKebabCase
            do {
                return try decoder.decode(DeviceInfo.self, from: Data(xmlString.utf8))
            } catch {
                logger.error("Error decoding DeviceInfo response \(error, privacy: .public)")
            }
        }
    } catch {
        logger.error("Error getting device info: \(error, privacy: .public)")
    }
    return nil
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
