import Foundation
import os
import SwiftData

typealias AppLink = SchemaV1.AppLink

extension AppLink: Decodable {
    public convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)

        let singleValueContainer = try decoder.singleValueContainer()
        let name = try singleValueContainer.decode(String.self)

        self.init(id: id, type: type, name: name)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        var svc = encoder.singleValueContainer()

        try svc.encode(name)
    }

    enum CodingKeys: String, CodingKey {
        case id, type
    }
}

// Models shouldn't be sendable
@available(*, unavailable)
extension AppLink: Sendable {}
