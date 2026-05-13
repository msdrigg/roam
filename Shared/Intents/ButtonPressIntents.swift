import AppIntents
#if !os(visionOS)
import WidgetKit
#endif
import Foundation
import SwiftUI

public enum PressCountAppEnum: String, AppEnum {
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case ten = "10"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Press Count")
    public static let caseDisplayRepresentations: [PressCountAppEnum: DisplayRepresentation] = [
        .one: "1",
        .two: "2",
        .three: "3",
        .four: "4",
        .five: "5",
        .six: "6",
        .seven: "7",
        .eight: "8",
        .nine: "9",
        .ten: "10",
    ]

    var intValue: Int {
        switch self {
        case .one:
            1
        case .two:
            2
        case .three:
            3
        case .four:
            4
        case .five:
            5
        case .six:
            6
        case .seven:
            7
        case .eight:
            8
        case .nine:
            9
        case .ten:
            10
        }
    }
}

public struct PlayIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PlayIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Press play", comment: "Title for play intent")
    public static let description = IntentDescription(LocalizedStringResource("Play or pause the media on the connected device", comment: "Description for play intent"))

    public init() {}

    public init(device: Device?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: Device?

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

public struct OkIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "OkIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Click Ok", comment: "Title for Ok intent")
    public static let description = IntentDescription(LocalizedStringResource("Click Ok on the device", comment: "Description for Ok intent"))

    public init() {}
    public init(device: Device?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: Device?

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

public struct MuteIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public var value: Never?

    public static let intentClassName = "MuteIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Toggle Mute", comment: "Title for mute intent")
    public static let description = IntentDescription(LocalizedStringResource("Mute or unmute the device", comment: "Description for mute intent"))
    public init() {}
    public init(device: Device?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: Device?

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

public enum TimedMuteDuration: String, AppEnum {
    case thirtySeconds = "30Seconds"
    case oneMinute = "1Minute"
    case twoMinutes = "2Minutes"
    case threeMinutes = "3Minutes"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Mute Duration")
    public static let caseDisplayRepresentations: [TimedMuteDuration: DisplayRepresentation] = [
        .thirtySeconds: "30 seconds",
        .oneMinute: "1 minute",
        .twoMinutes: "2 minutes",
        .threeMinutes: "3 minutes",
    ]

    var seconds: Int {
        switch self {
        case .thirtySeconds:
            30
        case .oneMinute:
            60
        case .twoMinutes:
            120
        case .threeMinutes:
            180
        }
    }
}

public struct TimedMuteIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "TimedMuteIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Mute temporarily", comment: "Title for timed mute intent")
    public static let description = IntentDescription(LocalizedStringResource("Mute the device for a duration, then unmute it", comment: "Description for timed mute intent"))

    public init() {}
    public init(device: Device?, duration: TimedMuteDuration = .thirtySeconds) {
        self.device = device
        self.duration = duration
    }

    @Parameter(title: "Device")
    public var device: Device?

    @Parameter(title: "Duration", default: .thirtySeconds, requestValueDialog: "How long should mute last?")
    public var duration: TimedMuteDuration

    public static var parameterSummary: some ParameterSummary {
        Summary("Mute \(\.$device) for \(\.$duration)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device, \.$duration)) { device, duration in
            DisplayRepresentation(
                title: LocalizedStringResource("Mute \(device!) for \(duration)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await setMuted(true, device: device)
        try await Task.sleep(nanoseconds: UInt64(duration.seconds) * 1_000_000_000)
        try await setMuted(false, device: device)
        return .result()
    }
}

public struct VolumeUpIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent,
    PredictableIntent
{
    public static let intentClassName = "VolumeUpIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Increase volume", comment: "Title for volume up intent")
    public static let description = IntentDescription(LocalizedStringResource("Increase the volume on the device", comment: "Description for volume up intent"))

    public init() {}
    public init(device: Device?) {
        self.device = device
        self.count = .one
    }

    @Parameter(title: "Device")
    public var device: Device?

    @Parameter(title: "Times", default: .one, requestValueDialog: "How many times?")
    public var count: PressCountAppEnum

    public static var parameterSummary: some ParameterSummary {
        Summary("Increase the volume \(\.$count) times on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device, \.$count)) { device, count in
            DisplayRepresentation(
                title: LocalizedStringResource("Increase the volume \(count) times on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeUp, device: device, count: count.intValue)
        return .result()
    }
}

public struct VolumeDownIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent,
    PredictableIntent
{
    public static let intentClassName = "VolumeDownIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Lower volume", comment: "Title for volume down intent")
    public static let description = IntentDescription(LocalizedStringResource("Lower the volume on the device", comment: "Description for volume down intent"))
    public init() {}
    public init(device: Device?) {
        self.device = device
        self.count = .one
    }

    @Parameter(title: "Device")
    public var device: Device?

    @Parameter(title: "Times", default: .one, requestValueDialog: "How many times?")
    public var count: PressCountAppEnum

    public static var parameterSummary: some ParameterSummary {
        Summary("Lower the volume \(\.$count) times on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$device, \.$count)) { device, count in
            DisplayRepresentation(
                title: LocalizedStringResource("Lower the volume \(count) times on \(device!)", comment: "Label on a configuration parameter")
            )
        }
    }

    public func perform() async throws -> some IntentResult {
        try await clickButton(button: .volumeDown, device: device, count: count.intValue)
        return .result()
    }
}

public struct PowerIntent: AppIntent, WidgetConfigurationIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "PowerIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Toggle Power", comment: "Title for power intent")
    public static let description = IntentDescription(LocalizedStringResource("Power on or off the device", comment: "Description for power intent"))

    public init() {}
    public init(device: Device?) {
        self.device = device
    }

    @Parameter(title: "Device")
    public var device: Device?

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

struct DeviceChoiceConfigurationProvider: AppIntentControlValueProvider {
    func previewValue(configuration: DeviceChoiceIntent) -> Device? {
        return configuration.selectedDevice
    }

    func currentValue(configuration: DeviceChoiceIntent) async throws -> Device? {
        return configuration.selectedDevice
    }
}
#endif
