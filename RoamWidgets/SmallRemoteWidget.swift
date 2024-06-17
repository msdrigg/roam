import AppIntents
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

#if !os(watchOS)
struct SmallDpadWidget: Widget {
    let dpad: [[RemoteButton?]] = [
        [
            .back, .up, .power,
        ],
        [
            .left, .select, .right,
        ],
        [
            .volumeDown, .down, .volumeUp,
        ],
    ]

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.roam.small-remote",
            intent: DeviceChoiceIntent.self,
            provider: SimpleRemoteControlProvider()
        ) { entry in
            SmallRemoteView(device: entry.device, controls: dpad)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

struct SmallMediaWidget: Widget {
    let controls: [[RemoteButton?]] = [
        [
            .instantReplay, .power, .options,
        ],
        [
            .rewind, .playPause, .fastForward,
        ],
        [
            .volumeDown, .mute, .volumeUp,
        ],
    ]

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.roam.media-remote",
            intent: DeviceChoiceIntent.self,
            provider: SimpleRemoteControlProvider()
        ) { entry in
            SmallRemoteView(device: entry.device, controls: controls)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}
#endif

#if DEBUG && !os(watchOS)
    #Preview(as: WidgetFamily.systemSmall) {
        SmallDpadWidget()
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

    #Preview(as: WidgetFamily.systemSmall) {
        SmallMediaWidget()
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

#if !os(macOS)
    struct SmallVolumeWidget: Widget {
        let dpad: [[RemoteButton?]] = [[
            .volumeDown, .mute, .volumeUp,
        ]]

        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.small-volume-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                #if os(watchOS)
                AccessoryGroupRemoteView(device: entry.device, controls: dpad[0])
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #else
                SmallRemoteView(device: entry.device, controls: dpad)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #endif
            }
            .supportedFamilies([.accessoryRectangular])
        }
    }

    struct SmallControlWidget: Widget {
        let dpad: [[RemoteButton?]] = [[
            .select, .power, .mute,
        ]]

        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.small-control-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                #if os(watchOS)
                AccessoryGroupRemoteView(device: entry.device, controls: dpad[0])
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #else
                SmallRemoteView(device: entry.device, controls: dpad)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
                #endif
            }
            .supportedFamilies([.accessoryRectangular])
        }
    }

#if os(watchOS)
    struct SmallPowerWidget: Widget {
        var button: RemoteButton = .power
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.circular-power-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                Button(intent: ButtonPressIntent(button, device: entry.device)) {
                    button.label
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.red)
                }
                .labelStyle(.iconOnly)
                .tint(Color.black)
            }
            .supportedFamilies([.accessoryCircular])
        }
    }

    struct SmallMuteWidget: Widget {
        var button: RemoteButton = .mute
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.circular-mute-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                Button(intent: ButtonPressIntent(button, device: entry.device)) {
                    button.label
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .labelStyle(.iconOnly)
                .tint(Color("AccentColor"))
            }
            .supportedFamilies([.accessoryCircular])
        }
    }

    struct SmallOkWidget: Widget {
        var button: RemoteButton = .select
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.circular-select-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                Button(intent: ButtonPressIntent(button, device: entry.device)) {
                    button.label
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .labelStyle(.iconOnly)
                .tint(Color("AccentColor"))
            }
            .supportedFamilies([.accessoryCircular])
        }
    }
#endif

#endif

#if DEBUG && !os(macOS)
    #Preview(as: WidgetFamily.accessoryRectangular) {
        SmallVolumeWidget()
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
