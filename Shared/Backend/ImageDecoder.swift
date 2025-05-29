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

    func decodeImage(data: Data, mimeType: String) async throws -> Data {
        let isWebP = mimeType == "image/webp"

        if isWebP {
            return try await withCheckedThrowingContinuation { continuation in
                // TODO: Stop with the global queue
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
    import Foundation
    func decodeImage(data: Data, mimeType: String) async throws -> Data {
        return data
    }
#endif
