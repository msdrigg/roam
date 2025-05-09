import AppIntents
import Foundation
import SwiftData
import OSLog

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct AppLinkAppEntity: Identifiable, Equatable, Hashable, Codable, Sendable {
    var name: String
    public var id: String
    public var type: String
    public var modelId: PersistentIdentifier?
    public var iconHash: String?

    init(name: String, id: String, type: String, modelId: PersistentIdentifier? = nil, iconHash: String? = nil) {
        self.name = name
        self.id = id
        self.type = type
        self.modelId = modelId
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

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)

        let singleValueContainer = try decoder.singleValueContainer()
        let name = try singleValueContainer.decode(String.self)

        self.init(name: name, id: id, type: type)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name
    }
}
