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
        public var lastSyncAt: Date?

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
        public var lastSyncAt: Date?

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
            MigrationStage.lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
        ]
    }

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }
}

private func getSharedModelContainer() -> ModelContainer? {
    let schema = Schema(
        versionedSchema: SchemaV5.self
    )

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(legacyContainerAppGroup),
    )

    do {
        return try ModelContainer(
            for: schema,
            migrationPlan: RoamSchemaMigrationPlan.self,
            configurations: modelConfiguration
        )
    } catch {
        Log.data.error("Error getting model container: \(error)")
        return nil
    }
}

@MainActor
public func migrateOffSwiftData() {
    if UserDefaults.standard.bool(forKey: UserDefaultKeys.didMigrateOffSwiftData) {
        return
    }
    UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.didMigrateOffSwiftData)
    let fl = FileLock(fileName: ".roamSwiftData.lock", appGroupIdentifier: mainAppGroup)

    do {
        try fl.withLock(mode: .exclusive) {
            guard let modelContainer = getSharedModelContainer() else {
                Log.data.warning("Failed to get model container")
                return
            }

            let context = modelContainer.mainContext

            // Get all non-deleted devices, all apps, and all messages from SwiftData
            let allDevices: [SchemaV5.Device] = try context.fetch(
                FetchDescriptor<SchemaV5.Device>(
                    predicate: #Predicate { $0.deletedAt == nil }
                )
            )

            let allApps: [SchemaV5.AppLink] = try context.fetch(
                FetchDescriptor<SchemaV5.AppLink>()
            )

            let allMessages: [SchemaV5.Message] = try context.fetch(
                FetchDescriptor<SchemaV5.Message>()
            )

            Log.data.info("Starting migration: \(allDevices.count) devices, \(allApps.count) apps, \(allMessages.count) messages")

            let dataHandler = RoamDataHandler.shared
            var deviceIds: [String] = []
            var hiddenDeviceIds: [String] = []

            // Migrate devices
            for swiftDataDevice in allDevices {
                Task {
                    do {
                        // Convert SwiftData device to new format
                        let newDevice = Device(
                            name: swiftDataDevice.name,
                            location: swiftDataDevice.location,
                            udn: swiftDataDevice.udn,
                            serial: swiftDataDevice.serial,
                            lastSentToWatch: swiftDataDevice.lastSentToWatch,
                            lastSelectedAt: swiftDataDevice.lastSelectedAt,
                            lastOnlineAt: swiftDataDevice.lastOnlineAt,
                            lastScannedAt: swiftDataDevice.lastScannedAt,
                            hiddenAt: swiftDataDevice.hiddenAt,
                            supportsDatagram: swiftDataDevice.supportsDatagram,
                            iconHash: swiftDataDevice.deviceIconHash,
                        )

                        // Insert device using RoamDataHandler
                        try await dataHandler.setDeviceDetails(device: newDevice)

                        // Track device in appropriate list
                        if swiftDataDevice.hiddenAt != nil {
                            hiddenDeviceIds.append(newDevice.id)
                        } else {
                            deviceIds.append(newDevice.id)
                        }

                        // Get apps for this device
                        let deviceApps = allApps.filter { $0.deviceUid == swiftDataDevice.udn }

                        // Convert SwiftData apps to new format
                        let newApps = deviceApps.compactMap { swiftDataApp in
                            guard let deviceId = swiftDataApp.deviceUid else {
                                return Optional<AppLink>.none
                            }
                            let newApp = AppLink(
                                name: swiftDataApp.name,
                                deviceId: deviceId,
                                id: swiftDataApp.id,
                                type: swiftDataApp.type,
                                iconHash: swiftDataApp.iconHash,
                            )
                            return newApp
                        }

                        // Store apps for device
                        try await dataHandler.setDeviceApps(deviceId: newDevice.id, apps: newApps)

                        Log.data.debug("Migrated device \(newDevice.name) with \(newApps.count) apps")

                    } catch {
                        Log.data.error("Failed to migrate device \(swiftDataDevice.name): \(error)")
                    }
                }
            }

            // Find device with most recent lastSelectedAt to make primary
            let primaryDevice = allDevices.max(by: { a, b in
                (a.lastSelectedAt ?? Date.distantPast) <
                (b.lastSelectedAt ?? Date.distantPast)
            })

            // Set primary device
            Task {
                if let primaryDevice = primaryDevice {
                    do {
                        try await dataHandler.makePrimaryDevice(id: primaryDevice.udn)
                        Log.data.info("Set primary device: \(primaryDevice.name)")
                    } catch {
                        Log.data.error("Failed to set primary device: \(error)")
                    }
                }
            }

            // TODO: Store all messages - implement when message system is complete
            // This will involve converting SchemaV5.Message to the new Message format
            // and storing them using the message system once it's implemented
            /*
            for swiftDataMessage in allMessages {
                let newMessage = Message(
                    id: swiftDataMessage.id,
                    message: swiftDataMessage.message,
                    author: convertMessageAuthor(swiftDataMessage.author),
                    fetchedBackend: swiftDataMessage.fetchedBackend
                )
                // await dataHandler.appendMessage(newMessage)
            }
            */

            Log.data.info("Migration completed successfully: \(deviceIds.count) visible devices, \(hiddenDeviceIds.count) hidden devices")

        }
    } catch {
        Log.data.error("Error doing swift data migration: \(error)")
        // Reset the migration flag on error so it can be retried
        UserDefaults.standard.setValue(false, forKey: UserDefaultKeys.didMigrateOffSwiftData)
    }
}

// MARK: - Helper Functions

private func convertMessageAuthor(_ swiftDataAuthor: SchemaV5.Message.AuthorType) -> Message.AuthorType{
    switch swiftDataAuthor {
    case .me:
        return .me
    case .support:
        return .support
    }
}
