import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Helpers")
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

public func kebabify(_ input: String) -> String {
    // Split input at capitals
    let split = input.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1-$2", options: .regularExpression)
    return split.lowercased()
}
