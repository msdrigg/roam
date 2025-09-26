import AppIntents
import Foundation
import OSLog

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct  AppLink: Identifiable, Equatable, Hashable, Codable, Sendable {
    var name: String
    public var id: String
    public var deviceId: String
    public var type: String
    public var iconHash: String?
    public var lastSyncAt: Date?

    init(name: String, deviceId: String, id: String, type: String, iconHash: String? = nil) {
        self.name = name
        self.id = id
        self.deviceId = deviceId
        self.type = type
        self.iconHash = iconHash
    }

    public var iconURL: URL? {
        guard let iconHash else { return nil }

        // Get the group container directory
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
            Log.data.error("Unable to get group container URL")
            return nil
        }

        return containerURL
            .appendingPathComponent("roku-icons", isDirectory: true)
            .appendingPathComponent(iconHash)
    }
}
