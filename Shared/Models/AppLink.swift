import Foundation
import os
import SwiftData

typealias AppLink = SchemaV5.AppLink

// Models shouldn't be sendable
@available(*, unavailable)
extension AppLink: Sendable {}

public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        AppLinkAppEntity(name: name, id: id, type: type, modelId: persistentModelID, iconHash: iconHash)
    }

    var iconURL: URL? {
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
