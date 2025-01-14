import Foundation
import os.log
import XMLCoder

struct DeviceInfo: Codable {
    let powerMode: String?
    let networkType: String?
    let ethernetMac: String?
    let wifiMac: String?
    let friendlyDeviceName: String?
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

func tryFetchDeviceIcon(location: String) async throws -> Data {
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

func fetchDeviceCapabilities(location: String) async throws -> DeviceCapabilities {
    let url = URL(string: "\(location)query/audio-device")!
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLDecoder()
    let audioDevice = try decoder.decode(AudioDevice.self, from: data)

    let isDatagramSupported = audioDevice.capabilities.allDestinations?.contains("datagram")
    let rtcpPort = audioDevice.rtpInfo?.rtcpPort

    return DeviceCapabilities(supportsDatagram: isDatagramSupported ?? false, rtcpPort: rtcpPort)
}

struct Apps: Decodable {
    let app: [AppLink]
}

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "FetchDevice"
)

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

public enum APIError: Swift.Error, LocalizedError {
    case badURLError(_ url: String)
}

func fetchDeviceApps(location: String) async throws -> [AppLinkAppEntity] {
    guard let url = URL(string: "\(location)query/apps") else {
        throw APIError.badURLError("\(location)query/apps")
    }
    let (data, _) = try await URLSession.shared.data(from: url)

    let decoder = XMLDecoder()
    let apps = try decoder.decode(Apps.self, from: data)

    return apps.app.map { $0.toAppEntity() }
}

func fetchAppIcon(location: String, appId: String) async throws -> Data {
    guard let url = URL(string: "\(location)query/icon/\(appId)") else {
        throw APIError.badURLError("\(location)query/icon/\(appId)")
    }
    return try await fetchURLIcon(url: url)
}

#if canImport(libwebp)
    import CoreGraphics
    import libwebp
    import UIKit

    public enum WebPError: Swift.Error, LocalizedError {
        case unexpectedPointerError // Something related pointer operation's error
        case unexpectedError(withMessage: String) // Something happened
        case unknownDecodingError
        case decodingError
        case decoderConfigError
    }

    private func inspect(_ webPData: Data) throws -> WebPBitstreamFeatures {
        let cFeature = UnsafeMutablePointer<WebPBitstreamFeatures>.allocate(capacity: 1)
        defer { cFeature.deallocate() }

        let status = try webPData.withUnsafeBytes { rawPtr -> VP8StatusCode in
            guard let bindedBasePtr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WebPError.unexpectedPointerError
            }

            return WebPGetFeatures(bindedBasePtr, webPData.count, &cFeature.pointee)
        }

        guard status == VP8_STATUS_OK else {
            throw WebPError.unexpectedError(withMessage: "Error VP8StatusCode=\(status.rawValue)")
        }

        return cFeature.pointee
    }

    private func decode(_ webPData: Data, config: inout WebPDecoderConfig) throws {
        var mutableWebPData = webPData

        try mutableWebPData.withUnsafeMutableBytes { rawPtr in

            guard let bindedBasePtr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WebPError.unknownDecodingError
            }

            let status = WebPDecode(bindedBasePtr, webPData.count, &config)
            if status != VP8_STATUS_OK {
                throw WebPError.decodingError
            }
        }
    }

    private func decode(_ webPData: Data) throws -> CGImage {
        let feature = try inspect(webPData)
        let height = Int(feature.height)
        let width = Int(feature.width)
        var config = WebPDecoderConfig()
        if WebPInitDecoderConfig(&config) == 0 {
            throw WebPError.decoderConfigError
        }
        config.options = WebPDecoderOptions()
        config.output.colorspace = MODE_RGBA

        try decode(webPData, config: &config)

        let decodedData: CFData = Data(bytesNoCopy: config.output.u.RGBA.rgba,
                                       count: config.output.u.RGBA.size,
                                       deallocator: .free) as CFData

        guard let provider = CGDataProvider(data: decodedData) else {
            throw WebPError.unexpectedError(withMessage: "Couldn't initialize CGDataProvider")
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo
            .premultipliedLast.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let renderingIntent = CGColorRenderingIntent.defaultIntent
        let bytesPerPixel = 4

        if let cgImage = CGImage(width: width,
                                 height: height,
                                 bitsPerComponent: 8,
                                 bitsPerPixel: 8 * bytesPerPixel,
                                 bytesPerRow: bytesPerPixel * width,
                                 space: colorSpace,
                                 bitmapInfo: bitmapInfo,
                                 provider: provider,
                                 decode: nil,
                                 shouldInterpolate: false,
                                 intent: renderingIntent)
        {
            return cgImage
        }

        throw WebPError.unexpectedError(withMessage: "Couldn't initialize CGImage")
    }

    func fetchURLIcon(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let isWebP = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String == "image/webp"

        if isWebP {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        let cgImage = try decode(data)
                        let webpImage = UIImage(cgImage: cgImage)
                        if let pngData = webpImage.pngData() {
                            continuation.resume(returning: pngData)
                        } else {
                            continuation.resume(throwing: NSError(domain: "AppIconError", code: 1, userInfo: nil))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        return data
    }
#else
    func fetchURLIcon(url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
#endif
