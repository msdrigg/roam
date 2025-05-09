#if !os(watchOS)
    import AppIntents
    import Foundation
    import SwiftData
    import SwiftUI
    import WidgetKit

    struct MediumRemoteWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.medium-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                MediumRemoteView(device: entry.device)
            }
            .supportedFamilies([.systemMedium])
        }
    }

    struct MediumRemoteView: View {
        var device: DeviceAppEntity?

        let dPad: [[RemoteButton?]] = [
            [.back, .up, .home],
            [.left, .select, .right],
            [nil, .down, nil],
        ]
        let controlGrid: [[RemoteButton?]] = [
            [.instantReplay, .power, .options],
            [.rewind, .playPause, .fastForward],
            [.mute, .volumeDown, .volumeUp],
        ]

        var body: some View {
            HStack {
                SmallRemoteView(device: device, controls: dPad)
                Spacer()
                SmallRemoteView(device: device, controls: controlGrid)
            }
            .containerBackground(Color("WidgetBackground"), for: .widget)
        }
    }

#if DEBUG
    #Preview(as: WidgetFamily.systemMedium) {
        MediumRemoteWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: getTestingAppLinks().map { $0.toAppEntity() }
        )
    }
#endif
#endif
