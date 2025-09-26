import OSLog
import UserNotifications
import SwiftUI
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

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
    guard let data = image.pngData() else {
        return nil
    }
    return await withCheckedContinuation { continuation in
        DispatchQueue.computation.async {
            let compressedData = compressPNG(image: data, maxFileSize: maxFileSize)
            continuation.resume(returning: compressedData)
        }
    }
}

func compressPNG(image: Data, maxFileSize: Int = 9 * 1024 * 1024) -> Data? {
    let originalPNGData = image

    if originalPNGData.count <= maxFileSize {
        return originalPNGData
    }

    var compressionQuality: CGFloat = 1.0

    while compressionQuality > 0.1 {
        if let compressedJPEG = UnifiedImage(data: image)?.jpegData(compressionQuality: compressionQuality),
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
    let hiddenPatterns = [":ninja:", ":command-share-diagnostics:", ":command_share_diagnostics:"]

    return hiddenPatterns.contains(where: message.hasPrefix)
}

func expandMessagingText(_ message: String) -> String {
    let replacements: [(Regex, String)] = [
        // swiftlint:disable:next force_try
        (try! Regex(":manually[-_]add[-_]tv:"), String(
            localized: ":manually-add-tv:",
            defaultValue: "You can find the instructions for how to manually add a TV here: https://roam.msd3.io/manually-add-tv/",
            comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
        )),
        // swiftlint:disable:next force_try
        (try! Regex(":manually[-_]add[-_]tv[-_]full:"), String(
            localized: ":manually-add-tv-full:",
            // swiftlint:disable:next line_length
            defaultValue: "Hi, it sounds like you are having trouble connecting to your Roku TV. If the Roam app isn't automatically detecting your TV, you can manually add it by following the instructions here: https://roam.msd3.io/manually-add-tv/",
            comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
        )),
        // swiftlint:disable:next force_try
        (try! Regex(":help[-_]share[-_]diagnostics:"), String(
            localized: ":help-share-diagnostics:",
            defaultValue: "To share diagnostics, click the plus button at the bottom of the chat window and then click \"Attach diagnostics\"",
            comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
        )),
        // swiftlint:disable:next force_try
        (try! Regex(":message[-_]from[-_]roam[-_]title:"), String(
            localized: ":message-from-roam-title:",
            defaultValue: "Message from Roam",
            comment: "Localize as 'Message from Roam'"
        ))
    ]

    var expandedMessage = message

    for (key, value) in replacements {
        expandedMessage = expandedMessage.replacing(key, with: value)
    }

    return expandedMessage
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
            #if os(macOS)
                Log.notifications.notice("Registering for remote notifications")
                NSApplication.shared.registerForRemoteNotifications()
            #elseif os(watchOS)
                Log.notifications.notice("Registering for remote notifications")
                WKApplication.shared().registerForRemoteNotifications()
            #else
                Log.notifications.notice("Registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }
}
#endif

#if !TEST && !CLI
func sendBackendError(_ message: String, logEntries: [LogEntry]? = nil, file: StaticString = #file, line: UInt = #line) async {
    let sendingMessage = ":ninja:\nFatal error logged: \(message)\n\nFile: \(file)\nLine: \(line)\n\nThis is likely a bug in the app."

    do {
        _ = try await sendMessageDirect(message: sendingMessage, attachment: nil).get()

        #if !CLI && !TEST && !WIDGET
        do {
            Log.backend.notice("Getting diagnostics to export")
            let entries = try logEntries ?? getLogEntries()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let codedEntries: Data = try encoder.encode(entries)
            let hash = fastHashData(data: codedEntries)
            let upload = AttachmentUpload(filename: "log-entries.json", dataHash: hash, dataSize: Int64(codedEntries.count), contentType: "application/json", id: UUID().uuidString)
            _ = try await sendMessageDirect(message: ":ninja:", attachment: upload, attachmentData: codedEntries).get()
            Log.backend.notice("Sent attachment to share diagnostics \(String(describing: upload), privacy: .public)")
        } catch {
            Log.backend.warning("Error sending diagnostics on command-share: \(error, privacy: .public)")
            _ = try await sendMessageDirect(message: ":ninja:\nError sending diagnostics on command-share\n\(error)", attachment: nil).get()
        }
        #endif
    } catch {
        Log.lifecycle.warning("Error sending fatal log to backend: \(error, privacy: .public)")
    }
}
#endif

public func loggedFatalError(_ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) -> Never {
    let message = message()

#if !TEST && !CLI
    if !runningInPreview {
        let group = DispatchGroup()
        group.enter()

        let didCompleteLock = OSAllocatedUnfairLock(initialState: false)

        Task {
            await sendBackendError(message, file: file, line: line)

            didCompleteLock.withLock { lock in
                lock = true
            }
            group.leave()
        }

        _ = group.wait(timeout: .now() + 15.0)

        let didComplete = didCompleteLock.withLock { lock in
            return lock
        }

        if didComplete {
            Log.lifecycle.warning("Error logged to backend before fatal error: \(message, privacy: .public)")
        } else {
            Log.lifecycle.warning("Backend logging timed out after 5 seconds")
        }
    }
#endif

    fatalError(message, file: file, line: line)
}

func fastHashData(data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

extension DispatchQueue {
    static var imagesWorkQueue: DispatchQueue {
        return DispatchQueue(
            label: "com.msdrigg.roam.images-work",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    static var networkQueue: DispatchQueue {
        return DispatchQueue(
            label: "com.msdrigg.roam.network",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }
}

#if !CLI && !TEST
func initialInstallationAfter(_ version: String) -> Bool {
    if let initialVersion = UserDefaults.standard.string(forKey: UserDefaultKeys.firstInstallVersion) {
        let after = initialVersion > version
        Log.lifecycle.notice("Getting install version after \(version, privacy: .public) after=\(after, privacy: .public)")
        return after
    } else {
        return false
    }
}
#endif

enum RoboMessage {
    case cantConnect
    case thirdPartyApps
}

@MainActor
// swiftlint:disable:next line_length force_try
let connectRegex = try! Regex("\\bconne|\\badd|\\bpair|\\bfind|\\blook|\\bscan|\\bencuentra|\\bip\\b|\\bpick up|\\btrouver ma télé\\b|\\bconex|\\bconecta|\\bsuche|\\bauftauch|\\bno puedo\\b|\\b无法连接\\b|\\b连接\\b|\\bconexão\\b|\\bconectar\\b|\\bnão consigo\\b|\\bkết nối\\b|\\bلا أستطيع\\b|\\bالاتصال\\b|\\b(اتصل|توصيل|ربط|شبك|اشبك)|\\bਕਨੈਕਟ\\b|\\bਹੋ ਨਹੀਂ ਸਕਦਾ\\b|\\bmaghanap ng tv\\b|\\bmagkonekta\\b|\\bverbinden\\b|\\btrovare la tv\\b|اشغل").ignoresCase()

@MainActor
// swiftlint:disable:next force_try
let thirdPartyAppsRegex = try! Regex("\\bwork|\\bvolume|\\bsound|\\bhome|\\bup and").ignoresCase()

@MainActor
func checkRoboMessage(_ message: String) -> RoboMessage? {
    if message.firstMatch(of: connectRegex) != nil {
        return RoboMessage.cantConnect
    }

    if message.firstMatch(of: thirdPartyAppsRegex) != nil {
        return RoboMessage.thirdPartyApps
    }

    return nil
}

func getHostPortDisplay(from urlString: String) -> String {
    let host = getHost(from: urlString)
    let port = getPort(from: urlString)
    if let port, port != 8060 {
        return "\(host):\(port)"
    } else {
        return host
    }
}

private func getHost(from urlString: String) -> String {
    guard let url = URL(string: addSchemeAndPort(to: urlString)), let host = url.host else {
        return urlString
    }
    return host
}

private func getPort(from urlString: String) -> Int? {
    guard let url = URL(string: addSchemeAndPort(to: urlString)) else {
        return nil
    }
    return url.port
}

func addSchemeAndPort(to urlString: String, scheme: String = "http", port: Int = 8060) -> String {
    let urlString = "http://" + urlString.replacing(/^.*:\/\//, with: { _ in "" })

    guard let url = URL(string: urlString),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
        return urlString
    }
    components.scheme = scheme
    components.port = url.port ?? port // Replace the port only if it's not already specified

    return (components.string ?? urlString).replacing(/\/*$/, with: { _ in "" }) + "/"
}

func getGlobalNewDeviceName() -> String {
    return String(localized: "New device")
}
