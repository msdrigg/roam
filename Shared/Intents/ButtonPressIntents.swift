import AppIntents
import WidgetKit
import Foundation
import SwiftData
import SwiftUI

#if !os(tvOS)
@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct PlayIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PlayIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Press play", comment: "Title for play intent")
    public static let description = IntentDescription(LocalizedStringResource("Play or pause the media on the connected device", comment: "Description for play intent"))

    public init() {}

    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Press play on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Press play on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .playPause, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct OkIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "OkIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Click Ok", comment: "Title for Ok intent")
    public static let description = IntentDescription(LocalizedStringResource("Click Ok on the device", comment: "Description for Ok intent"))

    public init() {}
    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Click Ok on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Click Ok on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .select, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct MuteIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public var value: Never?

    public static let intentClassName = "MuteIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Toggle Mute", comment: "Title for mute intent")
    public static let description = IntentDescription(LocalizedStringResource("Mute or unmute the device", comment: "Description for mute intent"))
    public init() {}
    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Toggle volume mute on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Toggle volume mute on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .mute, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct VolumeUpIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent,
    PredictableIntent
{
    public static let intentClassName = "VolumeUpIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Increase volume", comment: "Title for volume up intent")
    public static let description = IntentDescription(LocalizedStringResource("Increase the volume on the device", comment: "Description for volume up intent"))

    public init() {}
    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Increase the volume on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Increase the volume on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeUp, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct VolumeDownIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent,
    PredictableIntent
{
    public static let intentClassName = "VolumeDownIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Lower volume", comment: "Title for volume down intent")
    public static let description = IntentDescription(LocalizedStringResource("Lower the volume on the device", comment: "Description for volume down intent"))
    public init() {}
    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Lower the volume on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Lower the volume on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeDown, device: device)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct PowerIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PowerIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Toggle Power", comment: "Title for power intent")
    public static let description = IntentDescription(LocalizedStringResource("Power on or off the device", comment: "Description for power intent"))

    public init() {}
    public init(device: DeviceAppEntity?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: DeviceAppEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Power on or off \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: \.$device) { device in
            DisplayRepresentation(
                title: LocalizedStringResource("Power on or off \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .power, device: device)
        return .result()
    }
}

#if os(iOS)
@available(iOS 18.0, *)
extension PlayIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.playButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: PlayIntent(device: device)) {
                Label("Play/Pause", systemImage: "playpause")
                    .controlWidgetActionHint("Play or pause your TV")
            }
        }
        .displayName("Play/Pause")
        .description("A control that plays and pauses your TV")
    }
}

@available(iOS 18.0, *)
extension OkIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.okButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: OkIntent(device: device)) {
                Label("Select", systemImage: "square.and.arrow.down")
                    .controlWidgetActionHint("Select Ok on your TV")
            }
        }
        .displayName("Ok")
        .description("A control that makes a selection on your TV")
    }
}

@available(iOS 18.0, *)
extension MuteIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.muteButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: MuteIntent(device: device)) {
                Label("Mute/Unmute", systemImage: "speaker.slash")
                    .controlWidgetActionHint("Mute or unmute your TV")
            }
        }
        .displayName("Mute/Unmute")
        .description("A control that mutes or unmutes your TV")
    }
}

@available(iOS 18.0, *)
extension VolumeUpIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.volumeUpButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: VolumeUpIntent(device: device)) {
                Label("Raise volume", systemImage: "speaker.plus")
                    .controlWidgetActionHint("Raise the volume on your TV")
            }
        }
        .displayName("Raise volume")
        .description("A control that raises the volume on your TV")
    }
}

@available(iOS 18.0, *)
extension VolumeDownIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.volumeDownButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: VolumeDownIntent(device: device)) {
                Label("Lower Volume", systemImage: "speaker.minus")
                    .controlWidgetActionHint("Lower the volume on your TV")
            }
        }
        .displayName("Lower volume")
        .description("A control that lowers the volume on your TV")
    }
}

@available(iOS 18.0, *)
extension PowerIntent: ControlWidget {
    static let kind = "com.msdrigg.roam.powerButton"

    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: DeviceChoiceConfigurationProvider()
        ) { device in
            ControlWidgetButton(action: PowerIntent(device: device)) {
                Label("Toggle power", systemImage: "power")
                    .controlWidgetActionHint("Turns on or off your TV")
            }
        }
        .displayName("Toggle power")
        .description("A control that turns on or off your TV")
    }
}

@available(iOS 18.0, *)
struct DeviceChoiceConfigurationProvider: AppIntentControlValueProvider {
    func previewValue(configuration: DeviceChoiceIntent) -> DeviceAppEntity? {
        return configuration.selectedDevice
    }

    func currentValue(configuration: DeviceChoiceIntent) async throws -> DeviceAppEntity? {
        return configuration.selectedDevice
    }
}
#endif
#endif
