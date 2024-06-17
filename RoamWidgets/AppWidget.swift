import AppIntents
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

#if !os(watchOS)
    struct SmallAppWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.app-links",
                intent: DeviceAndAppChoiceIntent.self,
                provider: AppChoiceRemoteControlProvider()
            ) { entry in
                SmallAppView(device: entry.device, apps: entry.apps, rows: 2)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
            }
            .supportedFamilies([.systemSmall])
        }
    }

#if DEBUG
    #Preview("AppWidgetMid", as: WidgetFamily.systemSmall) {
        SmallAppWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: getTestingAppLinks().map { $0.toAppEntityWithIcon() }
        )
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: nil,
            apps: []
        )
    }
#endif
#endif

#if !os(macOS)
    struct SmallerAppWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.smaller-app-links",
                intent: DeviceAndAppChoiceIntent.self,
                provider: AppChoiceRemoteControlProvider()
            ) { entry in
                #if !os(watchOS)
                SmallAppView(device: entry.device, apps: Array(entry.apps.prefix(2)), rows: 1)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #else
                SmallAppView(device: entry.device, apps: Array(entry.apps.prefix(3)), rows: 1)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #endif
            }
            .supportedFamilies([.accessoryRectangular])
        }
    }

#if DEBUG
    #Preview("AppWidgetSmall", as: WidgetFamily.accessoryRectangular) {
        SmallerAppWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: Array(getTestingAppLinks().map { $0.toAppEntityWithIcon() }.prefix(2))
        )
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: nil,
            apps: []
        )
    }
#endif
#endif
