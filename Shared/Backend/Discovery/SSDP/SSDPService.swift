import Foundation

// swiftlint:disable:next force_try
private let headerRegex = try! NSRegularExpression(pattern: "^([^\r\n:]+): (.*)$", options: [.anchorsMatchLines])

public struct SSDPService: Sendable {
    public let host: String
    public let responseHeaders: [String: String]?
    public let location: String?
    public let server: String?
    public let searchTarget: String?
    public let uniqueServiceName: String?


    init(host: String, response: String) {
        self.host = host

        let headers = Self.parse(response)
        responseHeaders = headers

        location = headers["LOCATION"]
        server = headers["SERVER"]
        searchTarget = headers["ST"]
        uniqueServiceName = headers["USN"]
    }

    private static func parse(_ response: String) -> [String: String] {
        var result = [String: String]()

        let matches = headerRegex.matches(in: response, range: NSRange(location: 0, length: response.count))
        for match in matches {
            let keyCaptureGroupIndex = match.range(at: 1)
            let key = (response as NSString).substring(with: keyCaptureGroupIndex)
            let valueCaptureGroupIndex = match.range(at: 2)
            let value = (response as NSString).substring(with: valueCaptureGroupIndex)
            result[key.uppercased()] = value
        }

        return result
    }
}
