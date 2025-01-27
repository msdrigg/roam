import Foundation
import os
import SwiftData

typealias AppLink = SchemaV3.AppLink

extension AppLink {
    internal static func fetchAllRequest() -> FetchDescriptor<AppLink> {
        var fd = FetchDescriptor(
            predicate: #Predicate<AppLink> { _ in
                true
            },
            sortBy: [SortDescriptor(\AppLink.id)]
        )
        fd.relationshipKeyPathsForPrefetching = []
        fd.propertiesToFetch = [\.id, \.type, \.name, \.lastSelected, \.deviceUid, \.icon]

        return fd
    }
}

// Models shouldn't be sendable
@available(*, unavailable)
extension AppLink: Sendable {}

public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        AppLinkAppEntity(name: name, id: id, type: type, modelId: persistentModelID)
    }

    func toAppEntityWithIcon() -> AppLinkAppEntity {
        AppLinkAppEntity(name: name, id: id, type: type, modelId: persistentModelID, icon: icon)
    }
}
