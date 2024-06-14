// Copyright (c) 2017 Pierrick Rouxel

import Foundation

// swiftlint:disable:next force_try
private let headerRegex = try! NSRegularExpression(pattern: "^([^\r\n:]+): (.*)$", options: [.anchorsMatchLines])

public struct SSDPService: Sendable {
    /// The host of service
    public let host: String
    /// The headers of the original response
    public let responseHeaders: [String: String]?
    /// The value of `LOCATION` header
    public let location: String?
    /// The value of `SERVER` header
    public let server: String?
    /// The value of `ST` header
    public let searchTarget: String?
    /// The value of `USN` header
    public let uniqueServiceName: String?

    // MARK: Initialisation

    /**
         Initialize the `SSDPService` with the discovery response.

         - Parameters:
             - host: The host of service
             - response: The discovery response.
     */
    init(host: String, response: String) {
        self.host = host

        let headers = Self.parse(response)
        responseHeaders = headers

        location = headers["LOCATION"]
        server = headers["SERVER"]
        searchTarget = headers["ST"]
        uniqueServiceName = headers["USN"]
    }

    // MARK: Private functions

    /**
        Parse the discovery response.

        - Parameters:
            - response: The discovery response.
     */
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
