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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let elementText = try? decoder.singleValueContainer().decode(String.self)

        guard let name = try container.decodeIfPresent(String.self, forKey: .name) ?? elementText else {
            throw DecodingError.keyNotFound(CodingKeys.name, DecodingError.Context(
                codingPath: decoder.codingPath + [CodingKeys.name],
                debugDescription: "No value associated with key name."
            ))
        }

        self.name = name
        self.id = try container.decode(String.self, forKey: .id)
        self.deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        self.type = try container.decode(String.self, forKey: .type)
        self.iconHash = try container.decodeIfPresent(String.self, forKey: .iconHash)
        self.lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(id, forKey: .id)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(iconHash, forKey: .iconHash)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case id
        case deviceId
        case type
        case iconHash
        case lastSyncAt
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
