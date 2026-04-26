import Foundation

public struct SSDPService: Sendable {
    public let location: String?
    public let uniqueServiceName: String?

    init(host: String, response: String) {
        let headers = Self.parse(response)

        location = headers["LOCATION"]
        uniqueServiceName = headers["USN"]
    }

    private static func parse(_ response: String) -> [String: String] {
        var result = [String: String]()
        let headerRegex = /^([^\\r\\n:]+):\s*(.*)$/.anchorsMatchLineEndings()

        let matches = response.matches(of: headerRegex)
        for match in matches {
            let (_, key, value) = match.output
            result[key.uppercased()] = String(value)
        }

        return result
    }
}
