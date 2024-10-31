import Foundation
import os
import SwiftData

typealias Device = SchemaV2.Device

extension Device: Identifiable {
    public var id: PersistentIdentifier {
        persistentModelID
    }
}

public extension Device {
    func powerModeOn() -> Bool {
        powerMode == "PowerOn"
    }

    var displayHash: String {
        "\(name)-\(udn)-\(isOnline())-\(location)-\(String(describing: supportsDatagram))"
    }

    func isOnline() -> Bool {
        guard let lastOnlineAt else {
            return false
        }
        return Date().timeIntervalSince(lastOnlineAt) < 60
    }
}

func getHost(from urlString: String) -> String {
    guard let url = URL(string: addSchemeAndPort(to: urlString)), let host = url.host else {
        return urlString
    }
    return host
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

// Models shouldn't be sendable
@available(*, unavailable)
extension Device: Sendable {}
