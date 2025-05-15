import AppIntents
import Foundation
import OSLog
import SwiftData
import SwiftUI
import WidgetKit

struct DeviceChoiceTimelineEntity: TimelineEntry {
    var date: Date
    var device: DeviceAppEntity?
    var apps: [AppLinkAppEntity]
    var appIcons: [String: Image] = [:]
}

struct SimpleRemoteControlProvider: AppIntentTimelineProvider {
    typealias Intent = DeviceChoiceIntent
    typealias Entry = DeviceChoiceTimelineEntity

    func recommendations() -> [AppIntentRecommendation<DeviceChoiceIntent>] {
        [
            AppIntentRecommendation(intent: DeviceChoiceIntent(), description: Text("Roku Controls", comment: "Siri spotlight recommendation")),
        ]
    }

    func snapshot(for configuration: DeviceChoiceIntent, in _: Context) async -> DeviceChoiceTimelineEntity {
        let dataHandler = await RoamDataHandler()

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        let apps: [AppLinkAppEntity] = if let udn = targetDevice?.udn {
            (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
        } else {
            []
        }

        let entry = DeviceChoiceTimelineEntity(date: Date(), device: targetDevice, apps: apps)
        return entry
    }

    func timeline(for configuration: DeviceChoiceIntent, in ctx: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let dataHandler = await RoamDataHandler()

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        let apps: [AppLinkAppEntity] = if let udn = targetDevice?.udn {
            (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
        } else {
            []
        }
        let entryNow = DeviceChoiceTimelineEntity(date: Date.now, device: targetDevice, apps: apps)
        let timeline = Timeline(entries: [entryNow], policy: .after(Date.now.advanced(by: 3600 * 24)))
        return timeline
    }

    func placeholder(in _: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil, apps: [])
    }
}

struct AppChoiceRemoteControlProvider: AppIntentTimelineProvider {
    typealias Intent = DeviceAndAppChoiceIntent
    typealias Entry = DeviceChoiceTimelineEntity

    func recommendations() -> [AppIntentRecommendation<DeviceAndAppChoiceIntent>] {
        [
            AppIntentRecommendation(intent: DeviceAndAppChoiceIntent(), description: Text("Roku Apps", comment: "Siri spotlight recommendation")),
        ]
    }

    func snapshot(for configuration: DeviceAndAppChoiceIntent, in _: Context) async -> DeviceChoiceTimelineEntity {
        let dataHandler = await RoamDataHandler()

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        var apps: [AppLinkAppEntity] = []
        if let udn = targetDevice?.udn {
            var loadedApps = (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
            if configuration.manuallySelectApps {
                if let app1 = configuration.app1 {
                    loadedApps.insert(app1, at: 0)
                }
                if let app2 = configuration.app2 {
                    if loadedApps.count >= 1 {
                        loadedApps.insert(app2, at: 1)
                    } else {
                        loadedApps.append(app2)
                    }
                }
                if let app3 = configuration.app3 {
                    if loadedApps.count >= 2 {
                        loadedApps.insert(app3, at: 2)
                    } else {
                        loadedApps.append(app3)
                    }
                }
#if !os(watchOS)
                if let app4 = configuration.app4 {
                    if loadedApps.count >= 3 {
                        loadedApps.insert(app4, at: 3)
                    } else {
                        loadedApps.append(app4)
                    }
                }
#endif
            }
            apps = loadedApps
        }
        apps = Array(apps.prefix(4))

        var appIcons: [String: Image] = [:]
        for app in apps {
            if let url = app.iconURL,
               let icon = try? await loadThumbnailForUrl(url, maxSize: 120) {
                appIcons[app.id] = icon
            }
        }

        let entry = DeviceChoiceTimelineEntity(date: Date(), device: targetDevice, apps: apps, appIcons: appIcons)
        return entry
    }

    func timeline(for configuration: DeviceAndAppChoiceIntent,
                  in _: Context) async -> Timeline<DeviceChoiceTimelineEntity>
    {
        let dataHandler = await RoamDataHandler()

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        var apps: [AppLinkAppEntity] = []
        if let udn = targetDevice?.udn {
            var loadedApps = (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
            if configuration.manuallySelectApps {
                if let app1 = configuration.app1 {
                    loadedApps.insert(app1, at: 0)
                }
                if let app2 = configuration.app2 {
                    if loadedApps.count >= 1 {
                        loadedApps.insert(app2, at: 1)
                    } else {
                        loadedApps.append(app2)
                    }
                }
                if let app3 = configuration.app3 {
                    if loadedApps.count >= 2 {
                        loadedApps.insert(app3, at: 2)
                    } else {
                        loadedApps.append(app3)
                    }
                }
#if !os(watchOS)
                if let app4 = configuration.app4 {
                    if loadedApps.count >= 3 {
                        loadedApps.insert(app4, at: 3)
                    } else {
                        loadedApps.append(app4)
                    }
                }
#endif
            }
            apps = loadedApps
        }
        apps = Array(apps.prefix(4))

        var appIcons: [String: Image] = [:]
        for app in apps {
            if let url = app.iconURL,
               let icon = try? await loadThumbnailForUrl(url, maxSize: 120) {
                appIcons[app.id] = icon
            }
        }

        let entryNow = DeviceChoiceTimelineEntity(date: Date.now, device: targetDevice, apps: apps, appIcons: appIcons)
        let timeline = Timeline(entries: [entryNow], policy: .after(Date.now.advanced(by: 3600 * 24)))
        return timeline
    }

    func placeholder(in _: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil, apps: [], appIcons: [:])
    }
}
