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

    internal static func fetchAllRequest() -> FetchDescriptor<Device> {
        var fd = FetchDescriptor(
            predicate: #Predicate {
                $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\Device.name, order: .reverse)]
        )
        fd.relationshipKeyPathsForPrefetching = []
        fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]

        return fd
    }
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

// Models shouldn't be sendable
@available(*, unavailable)
extension Device: Sendable {}
