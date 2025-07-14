public let runningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

#if DEBUG
    import Foundation
    import SwiftData
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    func getTestingDevices() -> [Device] {
        let devices = [
            Device(
                name: String(localized: "Living Room TV"),
                location: "http://192.168.0.1:8060/",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0),
                udn: "TD1",
                serial: "1234567890"
            ),
            Device(
                name: String(localized: "Mom's TV"),
                location: "http://192.168.0.2:8060/",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0 - 24 * 60 * 60),
                udn: "TD2",
                serial: "1234567891"
            ),
        ]

        devices[0].supportsDatagram = true
        devices[1].supportsDatagram = false

        return devices
    }

    func getTestingAppLinks(deviceUid: String? = nil) -> [AppLink] {
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
            let link = AppLink(id: String(idx), type: "appl", name: name, iconHash: pngDataHash, deviceUid: deviceUid)
            link.lastSelected = Date().addingTimeInterval(-Double(idx))
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
                lastSelectedAt: Date.now - TimeInterval(i * 400),
                lastOnlineAt: Date.now - TimeInterval(i * 300),
                udn: UUID().uuidString,
                serial: UUID().uuidString
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
                    id: "app.id.\(j)",
                    type: "appl",
                    name: "App \(j)",
                    iconHash: pngDataHash,
                    deviceUid: device.udn
                ))
            }
        }
        return (apps, devices)
    }
#endif
