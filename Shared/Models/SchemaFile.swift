import Foundation
import OSLog
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 1)
    }

    @Model
    public final class Device: Hashable {
        private nonisolated static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Device.self)
        )

        @Attribute(.unique, originalName: "id") public var udn: String
        public var name: String
        public var location: String

        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?

        public var powerMode: String?
        public var networkType: String?
        public var wifiMAC: String?
        public var ethernetMAC: String?

        public var rtcpPort: UInt16?
        public var supportsDatagram: Bool?

        @Attribute(.externalStorage) public var deviceIcon: Data?

        public init(
            name: String,
            location: String,
            lastSelectedAt: Date? = nil,
            lastOnlineAt: Date? = nil,
            udn: String
        ) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
        }
    }

    @Model
    public final class AppLink: Identifiable {
        public var id: String
        public var type: String
        public var name: String
        public var lastSelected: Date?
        public var deviceUid: String?
        @Attribute(.externalStorage) public var icon: Data?

        init(id: String, type: String, name: String, icon: Data? = nil, deviceUid: String? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.icon = icon
            self.deviceUid = deviceUid
        }
    }

    @Model
    public final class Message: Identifiable {
        @Attribute(.unique) public var id: String
        var message: String
        var author: AuthorType
        var fetchedBackend: Bool
        var viewed: Bool = false

        enum AuthorType: String, Codable {
            case me
            case support
        }

        init(id: String, message: String, author: AuthorType, fetchedBackend: Bool = true, viewed: Bool = false) {
            self.id = id
            self.message = message
            self.author = author
            self.fetchedBackend = fetchedBackend
            self.viewed = viewed
        }
    }

    public static var models: [any PersistentModel.Type] {
        [Self.Device.self, Self.AppLink.self, Self.Message.self]
    }
}

public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 2)
    }

    @Model
    public final class Device: Hashable {
        private nonisolated static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Device.self)
        )

        @Attribute(.unique, originalName: "id") public var udn: String
        public var name: String
        public var location: String

        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?

        public var powerMode: String?
        public var networkType: String?
        public var wifiMAC: String?
        public var ethernetMAC: String?

        public var rtcpPort: UInt16?
        public var supportsDatagram: Bool?

        @Attribute(.externalStorage) public var deviceIcon: Data?

        public init(
            name: String,
            location: String,
            lastSelectedAt: Date? = nil,
            lastOnlineAt: Date? = nil,
            udn: String
        ) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
        }
    }

    @Model
    public final class AppLink: Identifiable {
        public var id: String
        public var type: String
        public var name: String
        public var lastSelected: Date?
        public var deviceUid: String?
        @Attribute(.externalStorage) public var icon: Data?

        init(id: String, type: String, name: String, icon: Data? = nil, deviceUid: String? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.icon = icon
            self.deviceUid = deviceUid
        }
    }

    @Model
    public final class Message: Identifiable {
        @Attribute(.unique) public var id: String
        var message: String
        var author: AuthorType
        var fetchedBackend: Bool
        var viewed: Bool = false
        var messageTitle: String?
        var robotMessage: Bool = false

        enum AuthorType: String, Codable {
            case me
            case support
        }

        init(id: String, message: String, author: AuthorType, fetchedBackend: Bool = true, viewed: Bool = false, messageTitle: String? = nil, robotMessage: Bool = false) {
            self.id = id
            self.message = message
            self.author = author
            self.fetchedBackend = fetchedBackend
            self.viewed = viewed
            self.robotMessage = robotMessage
            self.messageTitle = messageTitle
        }
    }

    public static var models: [any PersistentModel.Type] {
        [Self.Device.self, Self.AppLink.self, Self.Message.self]
    }
}

public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 3)
    }

    @Model
    public final class Device: Hashable {
        private nonisolated static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Device.self)
        )

        @Attribute(.unique, originalName: "id") public var udn: String
        public var name: String
        public var location: String

        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?

        public var powerMode: String?
        public var networkType: String?
        public var wifiMAC: String?
        public var ethernetMAC: String?

        public var rtcpPort: UInt16?
        public var supportsDatagram: Bool?

        @Attribute(.externalStorage) public var deviceIcon: Data?

        public init(
            name: String,
            location: String,
            lastSelectedAt: Date? = nil,
            lastOnlineAt: Date? = nil,
            udn: String
        ) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
        }
    }

    @Model
    public final class AppLink: Identifiable {
        public var id: String
        public var type: String
        public var name: String
        public var lastSelected: Date?
        public var deviceSortOrder: Int?
        public var deviceUid: String?
        @Attribute(.externalStorage) public var icon: Data?

        init(id: String, type: String, name: String, icon: Data? = nil, deviceUid: String? = nil, deviceSortOrder: Int? = nil, lastSelected: Date? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.icon = icon
            self.deviceUid = deviceUid
            self.deviceSortOrder = deviceSortOrder
            self.lastSelected = lastSelected
        }
    }

    @Model
    public final class Message: Identifiable {
        @Attribute(.unique) public var id: String
        var message: String
        var author: AuthorType
        var fetchedBackend: Bool
        var viewed: Bool = false
        var messageTitle: String?
        var robotMessage: Bool = false

        enum AuthorType: String, Codable {
            case me
            case support
        }

        init(id: String, message: String, author: AuthorType, fetchedBackend: Bool = true, viewed: Bool = false, messageTitle: String? = nil, robotMessage: Bool = false) {
            self.id = id
            self.message = message
            self.author = author
            self.fetchedBackend = fetchedBackend
            self.viewed = viewed
            self.robotMessage = robotMessage
            self.messageTitle = messageTitle
        }
    }

    public static var models: [any PersistentModel.Type] {
        [Self.Device.self, Self.AppLink.self, Self.Message.self]
    }
}

enum RoamSchemaMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
        ]
    }

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }
}
