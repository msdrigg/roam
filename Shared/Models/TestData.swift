import Foundation

public let runningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

#if DEBUG
    import SwiftUI
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    struct SampleDataPreviewModifier: PreviewModifier {
        static func makeSharedContext() async throws {
            try await RoamDataHandler.shared.loadTestDataForPreview()
        }

        func body(content: Content, context: Void) -> some View {
            content
        }
    }

    extension PreviewTrait where T == Preview.ViewTraits {
        @MainActor static var sampleData: Self = .modifier(SampleDataPreviewModifier())
    }

    func getTestingDevices() -> [Device] {
        var devices = [
            Device(
                name: String(localized: "Living Room TV"),
                location: "http://192.168.0.1:8060/",
                udn: "TD1",
                serial: "1234567890",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0),
            ),
            Device(
                name: String(localized: "Mom's TV"),
                location: "http://192.168.0.2:8060/",
                udn: "TD2",
                serial: "1234567891",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0 - 24 * 60 * 60),
            ),
        ]

        devices[0].supportsDatagram = true
        devices[1].supportsDatagram = false

        devices[0].supportsAudioSettings = true
        devices[1].supportsAudioSettings = false
        devices[1].isStick = true
        devices[1].modelName = "Roku Express 4K+"

        return devices
    }

    func getTestingAppLinks(deviceId: String? = nil) -> [AppLink] {
        let deviceId = deviceId ?? "testId"
        let appNames = [
            "Netflix", "Hulu", "Max",
            "YouTube", "Apple TV",
            "The Roku Channel", "Peacock TV",
            "Disney Plus", "YouTube TV",
            "Prime Video", "SHOWTIME",
            "Tubi - Free Movies & TV",
            "Paramount Plus", "Backdrops",
            "Lifetime Movie Club", "Lifetime",
            "WIS News 10", "Nintendo Switch"
        ]

        var links: [AppLink] = []
        for (idx, name) in appNames.enumerated() {
            let imageName = name
            let pngData = Data(fromAssetImage: imageName)
            let pngDataHash: String? = if let pngData { fastHashData(data: pngData) } else { nil }
            if let pngData, let pngDataHash {
                Task {
                    try? storeIconToDisk(iconData: pngData, hash: pngDataHash)
                }
            }
            let link = AppLink(name: name, deviceId: deviceId, id: String(idx), type: "appl", iconHash: pngDataHash)
            links.append(link)
        }
        return links
    }

    func getTestingMessages() -> [Message] {
        [
            Message(id: "0001", message: "HI", author: .me, fetchedBackend: false),
            Message(id: "0002", message: "BYE BRO", author: .support, fetchedBackend: false),
            Message(
                id: "0003",
                // swiftlint:disable:next line_length
                message: "BYE BRO (part two but this time with a lot more text. Does it wrap? Does it work? IDK???BYE BRO (part two but this time with a lot more text. Does it wrap? Does it work? IDK???",
                author: .support, fetchedBackend: false
            ),
            Message(
                id: "0004",
                message: "Resolved! (part two but this time with a lot more text. Does it wrap? Does it work? IDK???",
                author: .me, fetchedBackend: false
            ),
        ]
    }

    func getLoadTestingData() -> ([AppLink], [Device]) {
        var devices: [Device] = []
        var apps: [AppLink] = []
        var appCount = 0
        for i in 0 ... 5 {
            let device = Device(
                name: "Device \(i)",
                location: "http://192.168.8.24\(i):8060/)",
                udn: UUID().uuidString,
                serial: UUID().uuidString,
                lastSelectedAt: Date.now - TimeInterval(i * 400),
                lastOnlineAt: Date.now - TimeInterval(i * 300),
            )
            devices.append(device)
            for j in 0 ..< (i * 40) {
                appCount += 1
                let imageName = "\(j)"
                let pngData = Data(fromAssetImage: imageName)
                let pngDataHash: String? = if let pngData { fastHashData(data: pngData) } else { nil }
                if let pngData, let pngDataHash {
                    Task {
                        try? storeIconToDisk(iconData: pngData, hash: pngDataHash)
                    }
                }

                apps.append(AppLink(
                    name: "App \(j)",
                    deviceId: device.udn,
                    id: "app.id.\(j)",
                    type: "appl",
                    iconHash: pngDataHash,
                ))
            }
        }
        return (apps, devices)
    }
#endif
