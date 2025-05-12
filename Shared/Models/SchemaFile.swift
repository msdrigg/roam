import Foundation
import OSLog
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 1)
    }

    @Model
    public final class Device: Hashable {
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

public enum SchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 4)
    }

    @Model
    public final class Device: Hashable {
        @Attribute(originalName: "id") public var udn: String
        public var name: String
        public var location: String
        public var serial: String?

        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?

        public var hiddenAt: Date?

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
            udn: String,
            serial: String
        ) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
            self.serial = serial
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
        public var id: String
        var message: String
        var author: AuthorType
        var viewed: Bool = false
        var hidden: Bool = false

        // Handle sending
        var fetchedBackend: Bool
        var lastSendAttempt: Date?
        var nonce: String?

        // Send photos, videos or files
        @Attribute(.externalStorage)
        var attachmentsData: Data?

        @Attribute(.externalStorage)
        var unsentAttachmentData: Data?

        // Used for auto-reply messages
        var messageTitle: String?
        var robotMessage: Bool = false

        struct SentAttachment: Codable, Hashable {
            let id: String
            let data: Data
            let filename: String
            let mimetype: String
        }

        enum AuthorType: String, Codable {
            case me
            case support
        }

        @Transient
        lazy var attachments: [SentAttachment] = {
            guard let data = self.attachmentsData else {
                return []
            }

            let decoder = PropertyListDecoder()
            return (try? decoder.decode([SentAttachment].self, from: data)) ?? []
        }()

        @Transient
        lazy var unsentAttachment: AttachmentUpload? = {
            guard let data = self.unsentAttachmentData else {
                return nil
            }

            let decoder = PropertyListDecoder()
            return try? decoder.decode(AttachmentUpload.self, from: data)
        }()

        init(
            id: String, message: String, author: AuthorType,
            fetchedBackend: Bool = true, viewed: Bool = false,
            messageTitle: String? = nil, robotMessage: Bool = false,
            attachments: [SentAttachment] = [],
            unsentAttachment: AttachmentUpload? = nil, nonce: String? = nil
        ) {
            let encoder = PropertyListEncoder()
            self.id = id
            self.message = message
            self.author = author
            self.fetchedBackend = fetchedBackend
            self.viewed = viewed
            self.robotMessage = robotMessage
            self.messageTitle = messageTitle
            self.attachments = attachments
            self.hidden = isHiddenMessage(message)
            if let unsentAttachment {
                self.unsentAttachmentData = try? encoder.encode(unsentAttachment)
            } else {
                self.unsentAttachmentData = nil
            }
            self.attachmentsData = try? encoder.encode(attachments)
            self.nonce = nonce
        }
    }

    public static var models: [any PersistentModel.Type] {
        [Self.Device.self, Self.AppLink.self, Self.Message.self]
    }
}

public enum SchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 5)
    }

    @Model
    public final class Device: Hashable {
        @Attribute(originalName: "id") public var udn: String
        public var name: String
        public var location: String
        public var serial: String?

        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?

        public var hiddenAt: Date?

        public var powerMode: String?
        public var networkType: String?
        public var wifiMAC: String?
        public var ethernetMAC: String?

        public var rtcpPort: UInt16?
        public var supportsDatagram: Bool?

        public var deviceIconHash: String?

        public init(
            name: String,
            location: String,
            lastSelectedAt: Date? = nil,
            lastOnlineAt: Date? = nil,
            udn: String,
            serial: String
        ) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
            self.serial = serial
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
        public var deletedAt: Date?
        public var lastIconSyncAt: Date?

        public var iconHash: String?

        init(id: String, type: String, name: String, iconHash: String? = nil, deviceUid: String? = nil, deviceSortOrder: Int? = nil, lastSelected: Date? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.iconHash = iconHash
            self.deviceUid = deviceUid
            self.deviceSortOrder = deviceSortOrder
            self.lastSelected = lastSelected
        }
    }

    @Model
    public final class Message: Identifiable {
        public var id: String
        var message: String
        var author: AuthorType
        var viewed: Bool = false
        var hidden: Bool = false

        // Handle sending
        var fetchedBackend: Bool
        var lastSendAttempt: Date?
        var nonce: String?

        // Send photos, videos or files
        var attachmentsDataV2: Data?
        var unsentAttachmentDataV2: Data?

        // Used for auto-reply messages
        var messageTitle: String?
        var robotMessage: Bool = false

        enum AuthorType: String, Codable {
            case me
            case support
        }

        struct SentAttachment: Codable, Hashable {
            let id: String
            let dataHash: String
            let dataSize: Int64
            let filename: String
            let mimetype: String
        }

        @Transient
        lazy var attachments: [SentAttachment] = {
            guard let data = self.attachmentsDataV2 else {
                return []
            }

            let decoder = PropertyListDecoder()
            return (try? decoder.decode([SentAttachment].self, from: data)) ?? []
        }()

        @Transient
        lazy var unsentAttachment: AttachmentUpload? = {
            guard let data = self.unsentAttachmentDataV2 else {
                return nil
            }

            let decoder = PropertyListDecoder()
            return try? decoder.decode(AttachmentUpload.self, from: data)
        }()

        init(
            id: String, message: String,
            author: AuthorType,
            fetchedBackend: Bool = true,
            viewed: Bool = false,
            messageTitle: String? = nil,
            robotMessage: Bool = false,
            attachments: [SentAttachment] = [],
            unsentAttachment: AttachmentUpload? = nil,
            nonce: String? = nil
        ) {
            let encoder = PropertyListEncoder()
            self.id = id
            self.message = message
            self.author = author
            self.fetchedBackend = fetchedBackend
            self.viewed = viewed
            self.robotMessage = robotMessage
            self.messageTitle = messageTitle
            self.attachments = attachments
            self.hidden = isHiddenMessage(message)
            if let unsentAttachment {
                self.unsentAttachmentDataV2 = try? encoder.encode(unsentAttachment)
            } else {
                self.unsentAttachmentDataV2 = nil
            }
            self.attachmentsDataV2 = try? encoder.encode(attachments)
            self.nonce = nonce
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
            MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            MigrationStage.lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            MigrationStage.lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self)
        ]
    }

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }
}
