import Foundation
import Testing
@testable import Roam

struct RoamDatabaseTests {
    @Test func testDeviceAndAppsPersistAcrossOpen() throws {
        let urls = try makeTemporaryDatabaseURLs()
        let database = try RoamDatabase(databaseURL: urls.database, lockURL: urls.lock)

        let device = Device(
            name: "Living Room",
            location: "http://192.168.1.20:8060",
            udn: "roku:living-room",
            serial: "serial-1"
        )
        let apps = [
            AppLink(name: "Netflix", deviceId: device.id, id: "12", type: "appl", iconHash: "hash-1"),
            AppLink(name: "YouTube", deviceId: device.id, id: "837", type: "appl", iconHash: nil),
        ]

        try database.saveDevice(device)
        try database.saveDeviceApps(deviceId: device.id, apps: apps)
        try database.saveDeviceList([device.id], kind: .visible)
        try database.setPrimaryDevice(id: device.id)

        #expect(database.deviceList() == [device.id])
        #expect(database.primaryDevice()?.id == device.id)
        #expect(database.deviceApps(deviceId: device.id).map(\.id) == ["12", "837"])

        let reopened = try RoamDatabase(databaseURL: urls.database, lockURL: urls.lock)
        #expect(reopened.deviceList() == [device.id])
        #expect(reopened.primaryDevice()?.name == "Living Room")
        #expect(reopened.deviceApps(deviceId: device.id).map(\.name) == ["Netflix", "YouTube"])
    }

    @Test func testFailedWriteDoesNotMutateSnapshot() throws {
        let urls = try makeTemporaryDatabaseURLs()
        let database = try RoamDatabase(databaseURL: urls.database, lockURL: urls.lock)

        do {
            try database.saveDeviceList(["missing-device"], kind: .visible)
            Issue.record("Expected saveDeviceList to fail for a missing device")
        } catch {
            #expect(database.deviceList().isEmpty)
        }
    }

    private func makeTemporaryDatabaseURLs() throws -> (database: URL, lock: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoamDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            database: directory.appendingPathComponent("Roam.sqlite"),
            lock: directory.appendingPathComponent(".Roam.sqlite.lock")
        )
    }
}
