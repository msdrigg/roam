import OSLog
import SwiftUI

private let logger = Logger(subsystem: getLogSubsystem(), category: "Helpers")
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

    let result1: (String, [String: String])? = parseHuluUrl(url, host: host)
        ?? parseDisneyUrl(url, host: host) ?? parseAmazonPrimeUrl(url, host: host)
        ?? parseSlingUrl(url, host: host)
    let result2: (String, [String: String])? = parseYouTubeUrl(url, host: host)
        ?? parseMaxUrl(url, host: host) ?? parseTubiUrl(url, host: host) ?? parseNetflixUrl(url, host: host)
        ?? parseParamountUrl(url, host: host) ?? parsePeacockUrl(url, host: host) ?? parseRokuUrl(url, host: host)

    return result1 ?? result2
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
        logger.notice("Parsing amazon url\(url, privacy: .public)")
        let pathComponents = url.pathComponents
        // swiftlint:disable:next force_try
        if pathComponents.last?.starts(with: try! Regex("amzn.?\\.dv")) == true {
            if let lastComponent = pathComponents.last {
                logger.notice("Parsing 'amzn' amazon url \(lastComponent, privacy: .public)")
                parsedData["contentId"] = lastComponent
            }
            parsedData["mediaType"] = "movie"
        } else {
            logger.notice("Parsing standard amazon url \(pathComponents, privacy: .public)")
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
            logger.error("Error parsing kebab-case parameter name: \(keyPart.stringValue, privacy: .public)")
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
let globalHugeFixedVDLYMS: UInt32 = 1200

public func getLogSubsystem() -> String {
    return Bundle.main.bundleIdentifier ?? "com.msdrigg.roam"
}
