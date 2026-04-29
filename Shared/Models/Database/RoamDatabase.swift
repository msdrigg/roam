import Foundation
import Dispatch
import GRDB
import OSLog

final class RoamDatabase: @unchecked Sendable {
    enum DeviceListKind: String {
        case visible
        case hidden
    }

    private static let notificationName = "com.msdrigg.roam.database.changed"

    private let dbWriter: any DatabaseWriter
    private let fileLock: DatabaseFileLock?
    private let stateLock = NSRecursiveLock()
    private var snapshot: RoamDataSnapshot
    private var notificationObserver: UnsafeRawPointer?
    let isPersistent: Bool

    var onExternalChange: (@Sendable () -> Void)?

    static func openShared(containerURL: URL, legacyRootPath: String?) throws -> RoamDatabase {
        let databaseURL = containerURL.appendingPathComponent("Roam.sqlite")
        let lockURL = containerURL.appendingPathComponent(".Roam.sqlite.lock")
        return try RoamDatabase(databaseURL: databaseURL, lockURL: lockURL, legacyRootPath: legacyRootPath)
    }

    init(databaseURL: URL, lockURL: URL, legacyRootPath: String? = nil) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        fileLock = DatabaseFileLock(lockURL: lockURL)
        isPersistent = true

        let configuration = Self.makeConfiguration()

        dbWriter = try DatabasePool(path: databaseURL.path, configuration: configuration)
        snapshot = RoamDataSnapshot()

        try withExclusiveDatabaseLock {
            try RoamDatabase.migrator.migrate(dbWriter)
            try dbWriter.write { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
        }

        snapshot = try Self.loadSnapshot(from: dbWriter)

        if let legacyRootPath {
            try migrateLegacyFileDataIfNeeded(rootPath: legacyRootPath)
        }

        startExternalChangeObserver()
    }

    private init(volatileName: String) throws {
        fileLock = nil
        isPersistent = false
        dbWriter = try DatabaseQueue(named: volatileName, configuration: Self.makeConfiguration())
        snapshot = RoamDataSnapshot()

        try RoamDatabase.migrator.migrate(dbWriter)
        try dbWriter.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        snapshot = try Self.loadSnapshot(from: dbWriter)
    }

    static func openVolatile() throws -> RoamDatabase {
        try RoamDatabase(volatileName: "Roam-\(UUID().uuidString)")
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.label = "RoamDatabase"
        configuration.qos = .userInteractive
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true
        return configuration
    }

    deinit {
        if let notificationObserver {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                notificationObserver,
                CFNotificationName(Self.notificationName as CFString),
                nil
            )
        }
    }

    func deviceList() -> [String] {
        stateLock.withLock { snapshot.visibleDeviceIDs }
    }

    func hiddenDeviceList() -> [String] {
        stateLock.withLock { snapshot.hiddenDeviceIDs }
    }

    func device(id: String) -> Device? {
        stateLock.withLock { snapshot.devicesByID[id] }
    }

    func device(serial: String) -> Device? {
        stateLock.withLock {
            snapshot.devicesByID.values.first { $0.serial == serial }
        }
    }

    func deviceApps(deviceId: String) -> [AppLink] {
        stateLock.withLock { snapshot.appsByDeviceID[deviceId] ?? [] }
    }

    func primaryDevice() -> Device? {
        stateLock.withLock { snapshot.primaryDevice }
    }

    func primaryApps() -> [AppLink]? {
        stateLock.withLock { snapshot.primaryApps }
    }

    func messages() -> [Message] {
        stateLock.withLock { snapshot.messages }
    }

    func unreadMessageCount() -> Int {
        stateLock.withLock { snapshot.unreadMessageCount }
    }

    func saveDevice(_ device: Device) throws {
        try write { db in
            try Self.upsertDevice(device, db: db)
        }
    }

    func saveDevice(_ device: Device) async throws {
        try await writeAsync { db in
            try Self.upsertDevice(device, db: db)
        }
    }

    func deleteDevice(id: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM device_lists WHERE device_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM devices WHERE udn = ?", arguments: [id])
            try db.execute(sql: "UPDATE app_state SET primary_device_id = NULL WHERE id = 1 AND primary_device_id = ?", arguments: [id])
        }
    }

    func deleteDevice(id: String) async throws {
        try await writeAsync { db in
            try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM device_lists WHERE device_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM devices WHERE udn = ?", arguments: [id])
            try db.execute(sql: "UPDATE app_state SET primary_device_id = NULL WHERE id = 1 AND primary_device_id = ?", arguments: [id])
        }
    }

    func saveDeviceApps(deviceId: String, apps: [AppLink]) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [deviceId])
            for (index, app) in apps.enumerated() {
                try Self.insertApp(app, sortOrder: index, db: db)
            }
        }
    }

    func saveDeviceApps(deviceId: String, apps: [AppLink]) async throws {
        try await writeAsync { db in
            try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [deviceId])
            for (index, app) in apps.enumerated() {
                try Self.insertApp(app, sortOrder: index, db: db)
            }
        }
    }

    func saveDeviceList(_ devices: [String], kind: DeviceListKind) throws {
        try write { db in
            try Self.saveDeviceList(devices, kind: kind, db: db)
        }
    }

    func saveDeviceList(_ devices: [String], kind: DeviceListKind) async throws {
        try await writeAsync { db in
            try Self.saveDeviceList(devices, kind: kind, db: db)
        }
    }

    func setPrimaryDevice(id: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE app_state SET primary_device_id = ? WHERE id = 1", arguments: [id])
        }
    }

    func setPrimaryDevice(id: String) async throws {
        try await writeAsync { db in
            try db.execute(sql: "UPDATE app_state SET primary_device_id = ? WHERE id = 1", arguments: [id])
        }
    }

    func clearAll() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM message_attachments")
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM app_links")
            try db.execute(sql: "DELETE FROM device_lists")
            try db.execute(sql: "DELETE FROM devices")
            try db.execute(sql: "UPDATE app_state SET primary_device_id = NULL WHERE id = 1")
        }
    }

    func clearAll() async throws {
        try await writeAsync { db in
            try db.execute(sql: "DELETE FROM message_attachments")
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM app_links")
            try db.execute(sql: "DELETE FROM device_lists")
            try db.execute(sql: "DELETE FROM devices")
            try db.execute(sql: "UPDATE app_state SET primary_device_id = NULL WHERE id = 1")
        }
    }

    func saveMessage(_ message: Message) throws {
        try write { db in
            try Self.upsertMessage(message, db: db)
        }
    }

    func saveMessage(_ message: Message) async throws {
        try await writeAsync { db in
            try Self.upsertMessage(message, db: db)
        }
    }

    func saveMessages(_ messages: [Message]) throws {
        try write { db in
            for message in messages {
                try Self.upsertMessage(message, db: db)
            }
        }
    }

    func saveMessages(_ messages: [Message]) async throws {
        try await writeAsync { db in
            for message in messages {
                try Self.upsertMessage(message, db: db)
            }
        }
    }

    func deleteMessage(id: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [id])
        }
    }

    func deleteMessage(id: String) async throws {
        try await writeAsync { db in
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [id])
        }
    }

    func markMessagesViewed() throws {
        try write { db in
            try db.execute(sql: "UPDATE messages SET viewed = 1 WHERE viewed = 0")
        }
    }

    func markMessagesViewed() async throws {
        try await writeAsync { db in
            try db.execute(sql: "UPDATE messages SET viewed = 1 WHERE viewed = 0")
        }
    }

    func pendingMessage(nonce: String) -> Message? {
        stateLock.withLock {
            snapshot.messagesByID.values.first { message in
                message.nonce == nonce && !message.fetchedBackend
            }
        }
    }

    private func write(_ body: (Database) throws -> Void) throws {
        do {
            let nextSnapshot = try withExclusiveDatabaseLock {
                try dbWriter.writeWithoutTransaction { db in
                    try Self.performWrite(body, db: db)
                }
            }

            stateLock.withLock {
                snapshot = nextSnapshot
            }
            recordSuccessfulPersistentAccess()
            postExternalChangeNotification()
        } catch {
            let dataError = DataHandlerError.from(error: error)
            recordPersistentError(dataError)
            throw dataError
        }
    }

    private func writeAsync(_ body: @escaping @Sendable (Database) throws -> Void) async throws {
        do {
            let nextSnapshot = try await dbWriter.writeWithoutTransaction { [fileLock] db in
                if let fileLock {
                    return try fileLock.withExclusiveLock {
                        try Self.performWrite(body, db: db)
                    }
                }
                return try Self.performWrite(body, db: db)
            }

            stateLock.withLock {
                snapshot = nextSnapshot
            }
            recordSuccessfulPersistentAccess()
            postExternalChangeNotification()
        } catch {
            let dataError = DataHandlerError.from(error: error)
            recordPersistentError(dataError)
            throw dataError
        }
    }

    private func reloadSnapshot() throws {
        let nextSnapshot = try Self.loadSnapshot(from: dbWriter)
        stateLock.withLock {
            snapshot = nextSnapshot
        }
    }

    private func reloadSnapshotAsync() async throws {
        let nextSnapshot = try await Self.loadSnapshotAsync(from: dbWriter)
        stateLock.withLock {
            snapshot = nextSnapshot
        }
    }

    @discardableResult
    func reloadSnapshotIfChangedFromDisk() throws -> Bool {
        guard isPersistent else { return false }
        let currentRevision = stateLock.withLock { snapshot.revision }
        let diskRevision = try dbWriter.read { db in
            try Int64.fetchOne(db, sql: "SELECT revision FROM app_state WHERE id = 1") ?? 0
        }

        guard diskRevision != currentRevision else {
            return false
        }

        try reloadSnapshot()
        return true
    }

    @discardableResult
    func reloadSnapshotIfChangedFromDiskAsync() async throws -> Bool {
        guard isPersistent else { return false }
        let currentRevision = stateLock.withLock { snapshot.revision }
        let diskRevision = try await dbWriter.read { db in
            try Int64.fetchOne(db, sql: "SELECT revision FROM app_state WHERE id = 1") ?? 0
        }

        guard diskRevision != currentRevision else {
            return false
        }

        try await reloadSnapshotAsync()
        return true
    }

    func exportSnapshot() -> RoamDataSnapshot {
        stateLock.withLock { snapshot }
    }

    func mergeVolatileSnapshot(_ source: RoamDataSnapshot) throws {
        guard isPersistent else { return }

        let nextSnapshot = try withExclusiveDatabaseLock {
            try dbWriter.writeWithoutTransaction { db in
                try db.inTransaction {
                    let existingSnapshot = try Self.loadSnapshot(from: db)
                    for device in source.devicesByID.values {
                        try Self.upsertDevice(device, db: db)
                    }

                    for (deviceID, apps) in source.appsByDeviceID {
                        try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [deviceID])
                        for (index, app) in apps.enumerated() {
                            try Self.insertApp(app, sortOrder: index, db: db)
                        }
                    }

                    let hiddenIDs = Self.mergedList(source.hiddenDeviceIDs, with: existingSnapshot.hiddenDeviceIDs)
                    let visibleIDs = Self.mergedList(
                        source.visibleDeviceIDs,
                        with: existingSnapshot.visibleDeviceIDs
                    ).filter { !hiddenIDs.contains($0) }
                    try Self.saveDeviceList(visibleIDs, kind: .visible, db: db)
                    try Self.saveDeviceList(hiddenIDs, kind: .hidden, db: db)

                    if let primaryDeviceID = source.primaryDeviceID {
                        try db.execute(
                            sql: "UPDATE app_state SET primary_device_id = ? WHERE id = 1",
                            arguments: [primaryDeviceID])
                    }

                    for message in source.messages {
                        try Self.upsertMessage(message, db: db)
                    }

                    try db.execute(sql: "UPDATE app_state SET revision = revision + 1 WHERE id = 1")
                    return .commit
                }

                return try Self.loadSnapshot(from: db)
            }
        }

        stateLock.withLock {
            snapshot = nextSnapshot
        }
        recordSuccessfulPersistentAccess()
        postExternalChangeNotification()
    }

    private func withExclusiveDatabaseLock<T>(_ body: () throws -> T) throws -> T {
        if let fileLock {
            return try fileLock.withExclusiveLock(body)
        }
        return try body()
    }

    private static func performWrite(
        _ body: (Database) throws -> Void,
        db: Database
    ) throws -> RoamDataSnapshot {
        try db.inTransaction {
            try body(db)
            try db.execute(sql: "UPDATE app_state SET revision = revision + 1 WHERE id = 1")
            return .commit
        }

        return try Self.loadSnapshot(from: db)
    }

    private static func mergedList(_ preferred: [String], with existing: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for id in preferred + existing where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }

        return result
    }

    private func recordPersistentError(_ error: DataHandlerError) {
        guard isPersistent else { return }
        Task { @MainActor in
            DatabaseStatusMonitor.shared.setIssue(DatabaseStatusIssue(
                error: error,
                isVolatile: false,
                operation: .write))
        }
    }

    private func recordSuccessfulPersistentAccess() {
        guard isPersistent else { return }
        Task { @MainActor in
            DatabaseStatusMonitor.shared.clearIssue()
        }
    }

    private static func loadSnapshot(from dbReader: any DatabaseReader) throws -> RoamDataSnapshot {
        try dbReader.read { db in
            try loadSnapshot(from: db)
        }
    }

    private static func loadSnapshotAsync(from dbReader: any DatabaseReader) async throws -> RoamDataSnapshot {
        try await dbReader.read { db in
            try loadSnapshot(from: db)
        }
    }

    private static func loadSnapshot(from db: Database) throws -> RoamDataSnapshot {
        var snapshot = RoamDataSnapshot()

        let deviceRows = try Row.fetchAll(db, sql: "SELECT * FROM devices")
        for row in deviceRows {
            let device = decodeDevice(row)
            snapshot.devicesByID[device.id] = device
        }

        snapshot.visibleDeviceIDs = try String.fetchAll(
            db,
            sql: "SELECT device_id FROM device_lists WHERE list = ? ORDER BY sort_order, device_id",
            arguments: [DeviceListKind.visible.rawValue]
        )
        snapshot.hiddenDeviceIDs = try String.fetchAll(
            db,
            sql: "SELECT device_id FROM device_lists WHERE list = ? ORDER BY sort_order, device_id",
            arguments: [DeviceListKind.hidden.rawValue]
        )

        let appRows = try Row.fetchAll(db, sql: "SELECT * FROM app_links ORDER BY device_id, sort_order, app_id")
        for row in appRows {
            let app = decodeAppLink(row)
            snapshot.appsByDeviceID[app.deviceId, default: []].append(app)
        }

        let state = try Row.fetchOne(db, sql: "SELECT primary_device_id, revision FROM app_state WHERE id = 1")
        snapshot.primaryDeviceID = state?["primary_device_id"]
        snapshot.revision = state?["revision"] ?? 0

        let messageRows = try Row.fetchAll(db, sql: "SELECT * FROM messages")
        for row in messageRows {
            let message = decodeMessage(row)
            snapshot.messagesByID[message.id] = message
        }

        return snapshot
    }
}

private extension RoamDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS devices (
                    udn TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    location TEXT NOT NULL,
                    serial TEXT,
                    last_sent_to_watch DATETIME,
                    last_selected_at DATETIME,
                    last_sync_at DATETIME,
                    last_online_at DATETIME,
                    last_scanned_at DATETIME,
                    hidden_at DATETIME,
                    power_mode TEXT,
                    network_type TEXT,
                    wifi_mac TEXT,
                    ethernet_mac TEXT,
                    rtcp_port INTEGER,
                    supports_datagram INTEGER,
                    icon_hash TEXT
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS device_lists (
                    list TEXT NOT NULL,
                    sort_order INTEGER NOT NULL,
                    device_id TEXT NOT NULL REFERENCES devices(udn) ON DELETE CASCADE,
                    PRIMARY KEY (list, device_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_links (
                    device_id TEXT NOT NULL REFERENCES devices(udn) ON DELETE CASCADE,
                    app_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    icon_hash TEXT,
                    last_sync_at DATETIME,
                    sort_order INTEGER NOT NULL,
                    PRIMARY KEY (device_id, app_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    primary_device_id TEXT REFERENCES devices(udn) ON DELETE SET NULL,
                    revision INTEGER NOT NULL DEFAULT 0
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY NOT NULL,
                    message TEXT NOT NULL,
                    author TEXT NOT NULL,
                    viewed INTEGER NOT NULL,
                    hidden INTEGER NOT NULL,
                    fetched_backend INTEGER NOT NULL,
                    last_send_attempt DATETIME,
                    nonce TEXT,
                    sent_attachments_data BLOB,
                    unsent_attachment_data BLOB,
                    message_title TEXT,
                    robot_message INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS message_attachments (
                    message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    attachment_id TEXT NOT NULL,
                    data_hash TEXT NOT NULL,
                    data_size INTEGER NOT NULL,
                    filename TEXT NOT NULL,
                    mimetype TEXT NOT NULL,
                    is_unsent INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (message_id, attachment_id, is_unsent)
                )
                """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS devices_serial_idx ON devices(serial)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS app_links_device_idx ON app_links(device_id, sort_order)")
            try db.execute(sql: "INSERT OR IGNORE INTO app_state (id, revision) VALUES (1, 0)")
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "ALTER TABLE messages ADD COLUMN ai_message INTEGER NOT NULL DEFAULT 0")
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: "ALTER TABLE messages ADD COLUMN human_support_message INTEGER NOT NULL DEFAULT 0")
        }
        return migrator
    }

    static func upsertDevice(_ device: Device, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO devices (
                    udn, name, location, serial, last_sent_to_watch, last_selected_at,
                    last_sync_at, last_online_at, last_scanned_at, hidden_at, power_mode,
                    network_type, wifi_mac, ethernet_mac, rtcp_port, supports_datagram, icon_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(udn) DO UPDATE SET
                    name = excluded.name,
                    location = excluded.location,
                    serial = excluded.serial,
                    last_sent_to_watch = excluded.last_sent_to_watch,
                    last_selected_at = excluded.last_selected_at,
                    last_sync_at = excluded.last_sync_at,
                    last_online_at = excluded.last_online_at,
                    last_scanned_at = excluded.last_scanned_at,
                    hidden_at = excluded.hidden_at,
                    power_mode = excluded.power_mode,
                    network_type = excluded.network_type,
                    wifi_mac = excluded.wifi_mac,
                    ethernet_mac = excluded.ethernet_mac,
                    rtcp_port = excluded.rtcp_port,
                    supports_datagram = excluded.supports_datagram,
                    icon_hash = excluded.icon_hash
                """,
            arguments: [
                device.udn,
                device.name,
                device.location,
                device.serial,
                device.lastSentToWatch,
                device.lastSelectedAt,
                device.lastSyncAt,
                device.lastOnlineAt,
                device.lastScannedAt,
                device.hiddenAt,
                device.powerMode,
                device.networkType,
                device.wifiMAC,
                device.ethernetMAC,
                device.rtcpPort.map { Int($0) },
                device.supportsDatagram,
                device.iconHash,
            ])
    }

    static func insertApp(_ app: AppLink, sortOrder: Int, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO app_links (
                    device_id, app_id, name, type, icon_hash, last_sync_at, sort_order
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                app.deviceId,
                app.id,
                app.name,
                app.type,
                app.iconHash,
                app.lastSyncAt,
                sortOrder,
            ])
    }

    static func saveDeviceList(_ devices: [String], kind: DeviceListKind, db: Database) throws {
        try db.execute(sql: "DELETE FROM device_lists WHERE list = ?", arguments: [kind.rawValue])
        for (index, deviceID) in devices.enumerated() {
            try db.execute(
                sql: "INSERT INTO device_lists (list, sort_order, device_id) VALUES (?, ?, ?)",
                arguments: [kind.rawValue, index, deviceID])
        }
    }

    static func decodeDevice(_ row: Row) -> Device {
        let rtcpPortInt: Int? = row["rtcp_port"]
        var device = Device(
            name: row["name"],
            location: row["location"],
            udn: row["udn"],
            serial: row["serial"],
            lastSentToWatch: row["last_sent_to_watch"],
            lastSelectedAt: row["last_selected_at"],
            lastOnlineAt: row["last_online_at"],
            lastScannedAt: row["last_scanned_at"],
            hiddenAt: row["hidden_at"],
            powerMode: row["power_mode"],
            networkType: row["network_type"],
            wifiMAC: row["wifi_mac"],
            ethernetMAC: row["ethernet_mac"],
            rtcpPort: rtcpPortInt.flatMap(UInt16.init),
            supportsDatagram: row["supports_datagram"],
            iconHash: row["icon_hash"]
        )
        device.lastSyncAt = row["last_sync_at"]
        return device
    }

    static func decodeAppLink(_ row: Row) -> AppLink {
        var app = AppLink(
            name: row["name"],
            deviceId: row["device_id"],
            id: row["app_id"],
            type: row["type"],
            iconHash: row["icon_hash"]
        )
        app.lastSyncAt = row["last_sync_at"]
        return app
    }

    static func decodeMessage(_ row: Row) -> Message {
        let decoder = JSONDecoder()
        let sentData: Data? = row["sent_attachments_data"]
        let unsentData: Data? = row["unsent_attachment_data"]
        let sentAttachments = sentData.flatMap { try? decoder.decode([Message.SentAttachment].self, from: $0) } ?? []
        let unsentAttachment = unsentData.flatMap { try? decoder.decode(AttachmentUpload.self, from: $0) }

        var message = Message(
            id: row["id"],
            message: row["message"],
            author: Message.AuthorType(rawValue: row["author"]) ?? .support,
            fetchedBackend: row["fetched_backend"],
            viewed: row["viewed"],
            attachments: sentAttachments,
            unsentAttachment: unsentAttachment,
            nonce: row["nonce"],
            messageTitle: row["message_title"],
            robotMessage: row["robot_message"],
            aiMessage: row["ai_message"],
            humanSupportMessage: row["human_support_message"]
        )
        message.hidden = row["hidden"]
        message.lastSendAttempt = row["last_send_attempt"]
        return message
    }

    static func upsertMessage(_ message: Message, db: Database) throws {
        let encoder = JSONEncoder()
        let sentAttachmentsData = try encoder.encode(message.sentAttachments)
        let unsentAttachmentData = try message.unsentAttachment.map { try encoder.encode($0) }

        try db.execute(
            sql: """
                INSERT INTO messages (
                    id, message, author, viewed, hidden, fetched_backend, last_send_attempt,
                    nonce, sent_attachments_data, unsent_attachment_data, message_title, robot_message,
                    ai_message, human_support_message
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    message = excluded.message,
                    author = excluded.author,
                    viewed = excluded.viewed,
                    hidden = excluded.hidden,
                    fetched_backend = excluded.fetched_backend,
                    last_send_attempt = excluded.last_send_attempt,
                    nonce = excluded.nonce,
                    sent_attachments_data = excluded.sent_attachments_data,
                    unsent_attachment_data = excluded.unsent_attachment_data,
                    message_title = excluded.message_title,
                    robot_message = excluded.robot_message,
                    ai_message = excluded.ai_message,
                    human_support_message = excluded.human_support_message
                """,
            arguments: [
                message.id,
                message.message,
                message.author.rawValue,
                message.viewed,
                message.hidden,
                message.fetchedBackend,
                message.lastSendAttempt,
                message.nonce,
                sentAttachmentsData,
                unsentAttachmentData,
                message.messageTitle,
                message.robotMessage,
                message.aiMessage,
                message.humanSupportMessage,
            ])

        try db.execute(sql: "DELETE FROM message_attachments WHERE message_id = ?", arguments: [message.id])
        for attachment in message.sentAttachments {
            try db.execute(
                sql: """
                    INSERT INTO message_attachments (
                        message_id, attachment_id, data_hash, data_size, filename, mimetype, is_unsent
                    ) VALUES (?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [
                    message.id,
                    attachment.id,
                    attachment.dataHash,
                    attachment.dataSize,
                    attachment.filename,
                    attachment.mimetype,
                ])
        }

        if let attachment = message.unsentAttachment {
            try db.execute(
                sql: """
                    INSERT INTO message_attachments (
                        message_id, attachment_id, data_hash, data_size, filename, mimetype, is_unsent
                    ) VALUES (?, ?, ?, ?, ?, ?, 1)
                    """,
                arguments: [
                    message.id,
                    attachment.id,
                    attachment.dataHash,
                    attachment.dataSize,
                    attachment.filename,
                    attachment.contentType,
                ])
        }
    }
}

private extension RoamDatabase {
    func migrateLegacyFileDataIfNeeded(rootPath: String) throws {
        guard !UserDefaults.standard.bool(forKey: UserDefaultKeys.didMigrateFileDataToGRDB) else {
            return
        }

        guard stateLock.withLock({ snapshot.devicesByID.isEmpty }) else {
            UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.didMigrateFileDataToGRDB)
            return
        }

        let legacyFiles = FileDataHandler(rootPath: rootPath)
        guard legacyFiles.fileExists("devices.bin") || legacyFiles.fileExists("hiddenDevices.bin") else {
            UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.didMigrateFileDataToGRDB)
            return
        }

        Log.data.info("Starting legacy file data to GRDB migration")

        do {
            let visibleIDs = (try? legacyFiles.loadJSON("devices.bin", as: DeviceListData.self).devices) ?? []
            let hiddenIDs = (try? legacyFiles.loadJSON("hiddenDevices.bin", as: DeviceListData.self).devices) ?? []
            let allIDs = Array(Set(visibleIDs + hiddenIDs))

            try withExclusiveDatabaseLock {
                try dbWriter.write { db in
                    for id in allIDs {
                        let filename = "\(id).bin"
                        guard legacyFiles.fileExists(filename),
                              let device = try? legacyFiles.loadJSON(filename, as: Device.self)
                        else {
                            continue
                        }

                        try Self.upsertDevice(device, db: db)

                        let appsFilename = "\(id).apps.bin"
                        if legacyFiles.fileExists(appsFilename) {
                            let apps = (try? legacyFiles.loadJSON(appsFilename, as: [AppLink].self)) ?? []
                            try db.execute(sql: "DELETE FROM app_links WHERE device_id = ?", arguments: [id])
                            for (index, app) in apps.enumerated() {
                                try Self.insertApp(app, sortOrder: index, db: db)
                            }
                        }
                    }

                    try Self.saveDeviceList(visibleIDs, kind: .visible, db: db)
                    try Self.saveDeviceList(hiddenIDs, kind: .hidden, db: db)

                    if legacyFiles.fileExists("primaryDevice.bin"),
                       let primary = try? legacyFiles.loadJSON("primaryDevice.bin", as: Device.self) {
                        try db.execute(
                            sql: "UPDATE app_state SET primary_device_id = ? WHERE id = 1",
                            arguments: [primary.id])
                    } else if let firstVisibleID = visibleIDs.first {
                        try db.execute(
                            sql: "UPDATE app_state SET primary_device_id = ? WHERE id = 1",
                            arguments: [firstVisibleID])
                    }

                    try db.execute(sql: "UPDATE app_state SET revision = revision + 1 WHERE id = 1")
                }
            }

            try reloadSnapshot()
            UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.didMigrateFileDataToGRDB)
            Log.data.info("Finished legacy file data to GRDB migration")
        } catch {
            Log.data.error("Legacy file data migration failed: \(error, privacy: .public)")
            throw DataHandlerError.from(error: error)
        }
    }

    func startExternalChangeObserver() {
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        notificationObserver = observer

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let database = Unmanaged<RoamDatabase>.fromOpaque(observer).takeUnretainedValue()
                database.handleExternalChangeNotification()
            },
            Self.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    func handleExternalChangeNotification() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processExternalChangeNotification()
        }
    }

    private func processExternalChangeNotification() async {
        do {
            if try await reloadSnapshotIfChangedFromDiskAsync() {
                onExternalChange?()
            }
        } catch {
            Log.data.error("Failed to reload database snapshot after external change: \(error, privacy: .public)")
        }
    }

    func postExternalChangeNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
