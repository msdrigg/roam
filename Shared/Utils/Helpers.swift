import OSLog
import UserNotifications
import SwiftUI
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension String {
    func stripPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

#if !os(watchOS)
public func getModifiedCharacter(_ key: KeyEquivalent, modifiers: EventModifiers) -> Character {
    let scalarValue = key.character

    if modifiers.contains(.shift) || modifiers.contains(.capsLock) {
        let symbolMapping: [Character: Character] = [
            "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
            "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
            "`": "~", "-": "_", "=": "+", "[": "{", "]": "}",
            "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
        ]

        if let mappedSymbol = symbolMapping[scalarValue] {
            return mappedSymbol
        }

        // Uppercase alphabetic characters
        if scalarValue.isLowercase {
            return scalarValue.uppercased().first!
        }
    }

    // Return the original character if no mapping applies
    return scalarValue
}
#endif

public func kebabify(_ input: String) -> String {
    let split = input.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1-$2", options: .regularExpression)
    return split.lowercased()
}

extension Data {
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)

        var index = hexString.startIndex
        for _ in 0..<length {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard nextIndex <= hexString.endIndex else { return nil }
            let byteString = hexString[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    func toHexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}

public func parsePastedUrl(_ input: String) -> (String, [String: String])? {
    guard let url = URL(string: input), let host = url.host else { return nil }

    if let pattern = parseHuluUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseDisneyUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseAmazonPrimeUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseSlingUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseYouTubeUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseMaxUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseTubiUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseNetflixUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseRokuUrl(url, host: host) {
        return pattern
    }
    if let pattern = parseParamountUrl(url, host: host) {
        return pattern
    }
    if let pattern = parsePeacockUrl(url, host: host) {
        return pattern
    }

    return nil
}

private func parseSlingUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "46041"

    if host.contains("watch.sling.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            parsedData["mediaType"] = "movie"
            return (appId, parsedData)
        }
    }

    return nil
}

private func parseAmazonPrimeUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "13"

    if host.contains("amazon.com") {
        Log.connection.notice("Parsing amazon url\(url, privacy: .public)")
        let pathComponents = url.pathComponents
        // swiftlint:disable:next force_try
        if pathComponents.last?.starts(with: try! Regex("amzn.?\\.dv")) == true {
            if let lastComponent = pathComponents.last {
                Log.connection.notice("Parsing 'amzn' amazon url \(lastComponent, privacy: .public)")
                parsedData["contentId"] = lastComponent
            }
            parsedData["mediaType"] = "movie"
        } else {
            Log.connection.notice("Parsing standard amazon url \(pathComponents, privacy: .public)")
            parsedData["contentId"] = pathComponents.last{ piece in
                // swiftlint:disable:next force_try
                !piece.starts(with: try! Regex("ref"))
            }
            parsedData["mediaType"] = "movie"
        }
        return (appId, parsedData)
    }

    return nil
}

private func parseParamountUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "31440"

    if host.contains("paramountplus.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            parsedData["mediaType"] = "movie"
            return (appId, parsedData)
        }
    }

    return nil
}

private func parseHuluUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "2285"

    if host.contains("hulu.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            if pathComponents.contains("movie") {
                parsedData["mediaType"] = "movie"
            } else if pathComponents.contains("watch") {
                parsedData["mediaType"] = "episode"
            } else {
                parsedData["mediaType"] = "movie"
            }
            return (appId, parsedData)
        }
    }

    return nil
}

private func parseDisneyUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "291097"

    if host.contains("disneyplus.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            parsedData["mediaType"] = pathComponents.contains("series") ? "series" : "movie"
            return (appId, parsedData)
        }
    }

    return nil
}

private func parseRokuUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "151908"

    if host.contains("therokuchannel.roku.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            parsedData["mediaType"] = "movie"
            return (appId, parsedData)
        }
    }

    return nil
}

private func parsePeacockUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let appId = "593099"

    if host.contains("peacocktv.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {
            parsedData["contentId"] = pathComponents.last
            parsedData["mediaType"] = pathComponents.contains("movies") ? "movie" : "episode"
            return (appId, parsedData)
        }
    }

    return nil
}

private func parseTubiUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let tubiId = "41468"

    if host.contains("tubitv.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count <= 2 {
            return nil
        }
        if pathComponents[1] == "movies" {
            parsedData["contentId"] = pathComponents[2]
            parsedData["mediaType"] = "movie"
            return (tubiId, parsedData)
        } else if pathComponents[1] == "tv-shows" {
            parsedData["contentId"] = pathComponents[2]
            parsedData["mediaType"] = "episode"
            return (tubiId, parsedData)
        }
    }

    return nil
}

private func parseNetflixUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let netflixId = "12"

    if host.contains("netflix.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 && pathComponents[1] == "watch" {
            parsedData["contentId"] = pathComponents[2]
            parsedData["mediaType"] = "movie"
            return (netflixId, parsedData)
        }
    }

    return nil
}

private func parseMaxUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let maxId = "61322"

    if host.contains("max.com") {
        let pathComponents = url.pathComponents
        if pathComponents.count > 2 && pathComponents[1] == "video" && pathComponents[2] == "watch" {
            parsedData["contentId"] = pathComponents[3]
            parsedData["mediaType"] = "movie"
            return (maxId, parsedData)
        }
    }

    return nil
}

private func parseYouTubeUrl(_ url: URL, host: String) -> (String, [String: String])? {
    var parsedData: [String: String] = [:]
    let youtubeId = "837"

    if host.contains("youtube.com") || host.contains("youtu.be") {
        if let queryItems = URLComponents(string: url.absoluteString)?.queryItems {
            for item in queryItems where item.name == "v" {
                parsedData["contentId"] = item.value
                break
            }
        } else if host.contains("youtu.be"), let contentId = url.lastPathComponent as String? {
            parsedData["contentId"] = contentId
        }
        parsedData["mediaType"] = "episode"
        return (youtubeId, parsedData)
    }

    return nil
}

public func kebabParamDecodingStrategy() -> JSONDecoder.KeyDecodingStrategy {
    return JSONDecoder.KeyDecodingStrategy.custom { keySequence in
        let keyPart = keySequence.last!
        let segments = keyPart.stringValue.stripPrefix("param-").split(separator: "-")
        if segments.isEmpty {
            Log.connection.error("Error parsing kebab-case parameter name: \(keyPart.stringValue, privacy: .public)")
        }

        // Join camel case
        let joined = segments.makeIterator().enumerated().map { index, segment in
            if index == 0 {
                return segment.lowercased()
            } else {
                return segment.capitalized(with: Locale(identifier: "en_US"))
            }
        }.joined(separator: "")
        return AnyKey(stringValue: joined)
    }
}

public func kebabParamEncodingStrategy() -> JSONEncoder.KeyEncodingStrategy {
    return JSONEncoder.KeyEncodingStrategy.custom { keySequence in
        let keyPart = keySequence.last!.stringValue
        let stringValue = if keyPart == "request" || keyPart == "requestId" || keyPart == "status" || keyPart == "statusMsg" || keyPart == "contentData" || keyPart == "notify" {
            kebabify(keyPart)
        } else {
            "param-" + kebabify(keyPart)
        }

        return AnyKey(stringValue: stringValue)
    }
}

let globalHostRTPPort: UInt16 = 6970
let globalHostRTCPPort: UInt16 = 6971
let globalDefaultRemoteRTCPPort: UInt16 = 5150
let globalRTPPayloadType = 97
let globalClockRate = 48000
let globalPacketSizeMS: Int64 = 10
let globalHugeFixedVDLYMS: UInt32 = 600

public func installAborter() {
    let atexitResult = atexit({
        Log.lifecycle.error("Aborting due to exit being called")
        abort()
    })
    if atexitResult == 0 {
        Log.lifecycle.notice("Added call to atexit")
    } else {
        Log.lifecycle.error("FAILED to add call to atexit")
    }
}

@MainActor
public extension Binding {
    /// Returns a binding by mapping this binding's value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` this binding's value
    /// is set to `nil`.
    func mappedToBool<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(mappedTo: self)
    }
}

@MainActor
public extension Binding where Value == Bool {
    /// Creates a binding by mapping an optional value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` the value
    /// of `bindingToOptional`'s `wrappedValue` is set to `nil`.
    ///
    /// Setting the value of the produce binding to `true` does nothing and
    /// will log an error.
    ///
    /// - parameter bindingToOptional: A `Binding` to an optional value, used to calculate the `wrappedValue`.
    init(mappedTo bindingToOptional: Binding<(some Any)?>) {
        self.init(
            get: { bindingToOptional.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    bindingToOptional.wrappedValue = nil
                } else {
                    os_log(
                        .error,
                        "Optional binding mapped to optional has been set to `true`, which will have no effect. Current value: %@",
                        String(describing: bindingToOptional.wrappedValue)
                    )
                }
            }
        )
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }

    func jpegData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        
        // The compression quality for JPEG in NSBitmapImageRep is passed as a property
        // Value should be between 0.0 (maximum compression, lowest quality) and 1.0 (least compression, best quality)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: compressionQuality
        ]
        
        guard let jpegData = bitmapImage.representation(using: .jpeg, properties: properties) else {
            return nil
        }
        
        return jpegData
    }
}
typealias UnifiedImage = NSImage
#else
typealias UnifiedImage = UIImage
#endif

func compressPNGOffthread(image: UnifiedImage, maxFileSize: Int = 9 * 1024 * 1024) async -> Data? {
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let compressedData = compressPNG(image: image, maxFileSize: maxFileSize)
            continuation.resume(returning: compressedData)
        }
    }
}

func compressPNG(image: UnifiedImage, maxFileSize: Int = 9 * 1024 * 1024) -> Data? {
    guard let originalPNGData = image.pngData() else {
        return nil
    }

    if originalPNGData.count <= maxFileSize {
        return originalPNGData
    }

    var compressionQuality: CGFloat = 1.0

    while compressionQuality > 0.1 {
        if let compressedJPEG = image.jpegData(compressionQuality: compressionQuality),
           let finalPNGData = pngData(from: compressedJPEG),
           finalPNGData.count <= maxFileSize {
            return finalPNGData
        }

        compressionQuality -= 0.1
    }

    return nil
}

func pngData(from jpegData: Data) -> Data? {
    guard let uiImage = UnifiedImage(data: jpegData) else {
        return nil
    }
    
    return uiImage.pngData()
}

#if os(macOS)
extension NSImage {
    func compressedPNGData() async -> Data? {
        return await compressPNGOffthread(image: self)
    }
}
#else
extension UIImage {
    func compressedPNGData() async -> Data? {
        return await compressPNGOffthread(image: self)
    }
}
#endif

extension Data {
    init?(fromAssetImage imageName: String) {
#if os(macOS)
        let image = NSImage(named: imageName)

        if let pngData = image?.pngData() {
            self = pngData
        } else {
            return nil
        }
#else
        let image = UIImage(named: imageName, in: Bundle.main, with: nil)
        guard let data = image?.pngData() else {
            return nil
        }
        self = data
#endif
    }
}

#if os(iOS)
import Combine
import UIKit

/// Publisher to read keyboard changes.
enum KeyboardReadable { }

extension KeyboardReadable {
    @MainActor
    static var keyboardPublisher: AnyPublisher<Bool, Never> {
        Publishers.Merge(
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillShowNotification)
                .map { notification in
                    let rect = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect
                    return (rect?.height ?? 0) > 10
                },
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in false }
        )
        .eraseToAnyPublisher()
    }
}
#endif

func isHiddenMessage(_ message: String) -> Bool {
    let hiddenPatterns = [":ninja:", ":command-share-diagnostics:"]

    return hiddenPatterns.contains(where: message.hasPrefix)
}

func parseDiscordSnowflake(_ id: String) -> Date? {
    guard let snowflake = UInt64(id) else { return nil }

    let discordEpoch: UInt64 = 1_420_070_400_000 // Discord epoch in milliseconds (2015-01-01T00:00:00Z)
    let timestamp = (snowflake >> 22) + discordEpoch

    return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
}

func generateDiscordSnowflake(_ date: Date) -> String {
    let discordEpoch: UInt64 = 1_420_070_400_000 // Discord epoch in milliseconds (2015-01-01T00:00:00Z)
    let timestamp = UInt64(date.timeIntervalSince1970 * 1000) - discordEpoch
    let randomBits: UInt64 = 0b101010101010 // Example arbitrary bits (worker ID, process ID, increment)

    let snowflake = (timestamp << 22) | randomBits
    return String(snowflake)
}

#if !WIDGET
func requestNotificationPermission() {
    Log.notifications.notice("Requesting notification permission")
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
            Log.notifications.notice("Notification permission granted.")
            getNotificationSettings()
        } else if let error {
            Log.notifications.error("Notification permission denied with error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

func getNotificationSettings() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else {
            Log.notifications.notice("Not registering for remote notifications because notification permission is not granted. \(settings.authorizationStatus.rawValue, privacy: .public)")
            return
        }
        DispatchQueue.main.async {
            Log.notifications.notice("Registering for remote notifications")
            #if os(macOS)
                NSApplication.shared.registerForRemoteNotifications()
            #elseif !os(watchOS)
                UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }
}
#endif
