#if DEBUG
    import Foundation
    import SwiftData
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    func getTestingDevices() -> [Device] {
        [
            Device(
                name: "Living Room TV",
                location: "http://192.168.0.1:8060/",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0),
                udn: "TD1"
            ),
            Device(
                name: "2nd Living Room",
                location: "http://192.168.0.2:8060/",
                lastSelectedAt: Date(timeIntervalSince1970: 1_696_767_580.0 - 24 * 60 * 60),
                udn: "TD2"
            ),
        ]
    }

    public let testingContainer: ModelContainer = {
        do {
            let schema = Schema(
                versionedSchema: SchemaV1.self
            )
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier("group.com.msdrigg.roam.load")
            )

            let container = try ModelContainer(
                for: schema,
                migrationPlan: RoamSchemaMigrationPlan.self,
                configurations: [modelConfiguration]
            )

            Task { @MainActor in
                let context = container.mainContext
                container.deleteAllData()

                let (models, appLinks) = getLoadTestingData()
                for model in models {
                    context.insert(model)
                }

                for appLink in appLinks {
                    context.insert(appLink)
                }

                let messages = getTestingMessages()
                for message in messages {
                    context.insert(message)
                }
                try context.save()
            }
            return container
        } catch {
            fatalError("Failed to create container with error: \(error.localizedDescription)")
        }
    }()

    public let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )

            Task { @MainActor in
                let context = container.mainContext

                let models = getTestingDevices()
                for model in models {
                    context.insert(model)
                }

                let appLinks = getTestingAppLinks()
                for appLink in appLinks {
                    context.insert(appLink)
                }

                let messages = getTestingMessages()
                for message in messages {
                    context.insert(message)
                }
            }
            return container
        } catch {
            fatalError("Failed to create container with error: \(error.localizedDescription)")
        }
    }()

    func getTestingAppLinks() -> [AppLink] {
        [
            AppLink(id: "1", type: "appl", name: "Netflix", icon: nil, deviceUid: nil),
            AppLink(id: "5", type: "appl", name: "Hulu", icon: nil, deviceUid: nil),
            AppLink(id: "3", type: "appl", name: "Spotify with test long name", icon: nil, deviceUid: nil),
            AppLink(id: "2", type: "appl", name: "Showtime (no icon)"),
            AppLink(id: "4", type: "appl", name: "Disney another sweet long name", icon: nil, deviceUid: nil),
            AppLink(id: "6", type: "appl", name: "Disney another sweet long name", icon: nil, deviceUid: nil),
            AppLink(id: "7", type: "appl", name: "Disney another sweet long name", icon: nil, deviceUid: nil),
            AppLink(id: "7", type: "appl2", name: "Disney another", icon: nil, deviceUid: nil),
        ]
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
                udn: UUID().uuidString
            )
            devices.append(device)
            for j in 0 ..< (i * 40) {
                appCount += 1
                let imageName = "\(j)"
                #if os(macOS)
                    let image = NSImage(named: imageName)
                    var data: Data?

                    if let tiffData = image?.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData)
                    {
                        data = bitmapImage.representation(using: .png, properties: [:])
                    }
                #else
                    let image = UIImage(named: imageName, in: Bundle.main, with: nil)
                    let data = image?.pngData()
                #endif

                apps.append(AppLink(
                    id: "app.id.\(j)",
                    type: "appl",
                    name: "App \(j)",
                    icon: data,
                    deviceUid: device.udn
                ))
            }
        }
        return (apps, devices)
    }
#endif
