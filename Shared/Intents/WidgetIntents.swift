import AppIntents
import Foundation
import os

public struct OpenDeviceIntent: OpenIntent {
    public typealias Value = Device

    public init() {}
    public static let title: LocalizedStringResource = LocalizedStringResource("Open a device", comment: "Configuration title for a settings page")

    public static let openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    public var target: Device

    @MainActor
    public func perform() async throws -> some IntentResult {
        try await RoamDataHandler.shared.makePrimaryDevice(id: target.id)
        return .result()
    }
}

public struct DeviceChoiceIntent: AppIntent, WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Choose a device", comment: "Configuration title for a settings page")
    public static let description = IntentDescription(LocalizedStringResource("Choose which device to target", comment: "Configuration description for a settings page"))

    public init() {}

    @Parameter(
        title: LocalizedStringResource("Manually select which device to remote control", comment: "Configuration field title controlling whether or not devices are manually selected"),
        default: false
    )
    public var manuallySelectDevice: Bool

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    public var device: Device?

    public static var parameterSummary: some ParameterSummary {
        When(\.$manuallySelectDevice, .equalTo, true) {
            Summary {
                \.$manuallySelectDevice
                \.$device
            }
        } otherwise: {
            Summary {
                \.$manuallySelectDevice
            }
        }
    }

    public var selectedDevice: Device? {
        if !manuallySelectDevice {
            return nil
        }

        return device
    }

    // Xcode 26 / iOS 26 SDK: AppIntent and ControlConfigurationIntent both
    // expose a default `perform()` witness, making the conformance ambiguous.
    // Configuration intents don't actually act at perform-time; this explicit
    // override resolves the ambiguity.
    public func perform() async throws -> some IntentResult {
        return .result()
    }
}

#if os(iOS)
extension DeviceChoiceIntent: ControlConfigurationIntent {}
#endif

public struct DeviceAndAppChoiceIntent: AppIntent, WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Choose a device and apps", comment: "Configuration title for a settings page")
    public static let description = IntentDescription(LocalizedStringResource("Choose which device to target and select apps to view", comment: "Configuration description for a settings page"))

    public init() {}

    @Parameter(
        title: LocalizedStringResource(
            "Manually select which device to remote control",
            comment: "Configuration field title controlling whether or not devices are manually selected"
        ),
        default: false
    )
    public var manuallySelectDevice: Bool

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    public var device: Device?

    @Parameter(title: LocalizedStringResource("Manually select which apps to show", comment: "Configuration field title controlling whether or not apps are manually selected"), default: false)
    public var manuallySelectApps: Bool

    @Parameter(title: LocalizedStringResource("App 1", comment: "Configuration field title for selecting the first app"))
    public var app1: AppLink?

    @Parameter(title: LocalizedStringResource("App 2", comment: "Configuration field title for selecting the second app"))
    public var app2: AppLink?

    @Parameter(title: LocalizedStringResource("App 3", comment: "Configuration field title for selecting the third app"))
    public var app3: AppLink?

    @Parameter(title: LocalizedStringResource("App 4", comment: "Configuration field title for selecting the fourth app"))
    public var app4: AppLink?

    public static var parameterSummary: some ParameterSummary {
        When(\.$manuallySelectDevice, .equalTo, true) {
            When(\.$manuallySelectApps, .equalTo, true) {
                Summary {
                    \.$manuallySelectDevice
                    \.$device
                    \.$manuallySelectApps
                    \.$app1
                    \.$app2
                    \.$app3
                    \.$app4
                }
            } otherwise: {
                Summary {
                    \.$manuallySelectDevice
                    \.$device
                    \.$manuallySelectApps
                }
            }
        } otherwise: {
            When(\.$manuallySelectApps, .equalTo, true) {
                Summary {
                    \.$manuallySelectDevice
                    \.$manuallySelectApps
                    \.$app1
                    \.$app2
                    \.$app3
                    \.$app4
                }
            } otherwise: {
                Summary {
                    \.$manuallySelectDevice
                    \.$manuallySelectApps
                }
            }
        }
    }

    public var selectedDevice: Device? {
        if !manuallySelectDevice {
            return nil
        }

        return device
    }
}

public struct ButtonPressIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "ButtonPressIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Press a button", comment: "Configuration title for a button press action")
    public static let description = IntentDescription(LocalizedStringResource("Press a button on the connected device", comment: "Configuration description for a button press action"))

    public init() {}

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    var device: Device?

    @Parameter(title: LocalizedStringResource("Button", comment: "Configuration field title for a button selection field"))
    var button: RemoteButtonAppEnum

    @Parameter(
        title: LocalizedStringResource("Times", comment: "Configuration field title for a repeat count"),
        default: 1,
        controlStyle: .stepper,
        inclusiveRange: (1, 100),
        requestValueDialog: "How many times?"
    )
    var count: Int

    public static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$button) \(\.$count) times on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$button, \.$count, \.$device)) { button, count, device in
            DisplayRepresentation(
                title: LocalizedStringResource("Press \(button) \(count) times on \(device!)", comment: "Title for a shortcut action")
            )
        }
    }

    public init(_ button: RemoteButton, device: Device?) {
        self.button = button.buttonAppEnum
        self.device = device
        self.count = 1
    }

    public func perform() async throws -> some IntentResult {
        Log.userInteraction.debug(
            "Pressing widget button \(button.button.apiValue ?? "nil") \(count) times on device \(device?.name ?? "nil")"
        )

        try await clickButton(button: button.button, device: device, count: count)

        return .result()
    }
}

public func clickButton(button: RemoteButton, device: Device?, count: Int = 1) async throws {
    let pressCount = min(max(count, 1), 100)
    Log.userInteraction.notice("Pressing widget button \(button.apiValue ?? "nil", privacy: .public) \(pressCount, privacy: .public) times on device \(device?.name ?? "nil", privacy: .public)")

    let targetDevice = try await resolvedIntentDevice(device)

    #if os(watchOS)
    if let deviceKey = button.apiValue {
        for _ in 0..<pressCount {
            let success = await sendKeyToDeviceRawNotRecommended(
                location: targetDevice.location,
                key: deviceKey,
                macs: targetDevice.macs()
            )
            if !success {
                Log.userInteraction.warning("Error sending key to device")
                throw IntentError.deviceNotConnectable
            }
        }
    }
    #else
    do {
        try await withTimeout(delay: 5) {
            do {
                guard let url = URL(string: targetDevice.location) else {
                    throw IntentError.deviceNotConnectable
                }
                try await ECPWebsocketClient(location: url).oneOff { session in
                    for _ in 0..<pressCount {
                        try await session.pressButton(button)
                    }
                }
            } catch {
                Log.userInteraction.error("Error creating ECPSession or pressing button: \(error, privacy: .public)")
                throw IntentError.deviceNotConnectable
            }
        }
    } catch is TimeoutError {
        Log.userInteraction.warning("Timeout pressing button from intent")
        throw IntentError.deviceNotConnectable
    }
    #endif
}

public func setMuted(_ muted: Bool, device: Device?) async throws {
    let targetDevice = try await resolvedIntentDevice(device)
    let currentlyMuted = try await fetchMutedState(device: targetDevice)
    guard currentlyMuted != muted else {
        return
    }

    try await clickButton(button: .mute, device: targetDevice)
}

private func resolvedIntentDevice(_ device: Device?) async throws -> Device {
    let dataHandler = try await RoamDataHandler.sharedChecked()

    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await dataHandler.requestPrimaryDevice()
    }

    guard let targetDevice else {
        Log.userInteraction.warning("Trying to press button with no device available")
        throw IntentError.noSavedDevices
    }

    return targetDevice
}

private func fetchMutedState(device: Device) async throws -> Bool {
    do {
        return try await withTimeout(delay: 5) {
            guard let url = URL(string: "\(device.location)query/audio-device") else {
                throw IntentError.deviceNotConnectable
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = XMLStreamDecoder()
            return try decoder.decode(AudioDevice.self, from: data).globalInfo.muted
        }
    } catch is TimeoutError {
        Log.userInteraction.warning("Timeout checking mute state from intent")
        throw IntentError.deviceNotConnectable
    } catch {
        Log.userInteraction.error("Error checking mute state from intent: \(error, privacy: .public)")
        throw IntentError.deviceNotConnectable
    }
}

public func launchApp(app: AppLink, device: Device?) async throws {
    let dataHandler = try await RoamDataHandler.sharedChecked()

    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await dataHandler.requestPrimaryDevice()
    }

    if let targetDevice {
        #if os(watchOS)
        do {
            try await openApp(location: targetDevice.location, app: app.id)
        } catch {
            Log.userInteraction.error("Error opening app: \(error, privacy: .public)")
            throw IntentError.deviceNotConnectable
        }
        #else
        do {
            guard let url = URL(string: targetDevice.location) else {
                throw IntentError.deviceNotConnectable
            }
            try await ECPWebsocketClient(location: url).oneOff { session in
                try await session.launchApp(app.id)
            }
        } catch {
            Log.userInteraction.error("Error creating ECPSession or launching app: \(error, privacy: .public)")
            throw IntentError.deviceNotConnectable
        }
        #endif
    } else {
        throw IntentError.noSavedDevices
    }
}

private enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noSavedDevices
    case deviceNotConnectable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noSavedDevices: LocalizedStringResource("No saved devices", comment: "Error message description")
        case .deviceNotConnectable: LocalizedStringResource("Couldn't connect to the device", comment: "Error message description")
        }
    }
}

extension  AppLink: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("TV App", comment: "TV App Selection option"))
    public static let defaultQuery =  AppLinkQuery()

    public struct  AppLinkQuery: EntityQuery {
        @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent

        public init() {}

        public func entities(for identifiers: [AppLink.ID]) async throws -> [ AppLink] {
            let appLinkActor = try await RoamDataHandler.sharedChecked()
            var deviceId = launchAppIntent?.device.udn
            if deviceId == nil {
                 deviceId = await appLinkActor.requestPrimaryDevice()?.id
            }

            guard let deviceId else {
                throw IntentError.noSavedDevices
            }

            return await appLinkActor.requestDeviceApps(deviceId: deviceId).filter { app in
                identifiers.contains(app.id)
            }
        }

        func entities(matching string: String) async throws -> [ AppLink] {
            let appLinkActor = try await RoamDataHandler.sharedChecked()
            var deviceId = launchAppIntent?.device.udn
            if deviceId == nil {
                 deviceId = await appLinkActor.requestPrimaryDevice()?.id
            }

            guard let deviceId else {
                throw IntentError.noSavedDevices
            }

            return await appLinkActor.requestDeviceApps(deviceId: deviceId).filter { app in
                app.name ~= string
            }
        }

        public func suggestedEntities() async throws -> [ AppLink] {
            let appLinkActor = try await RoamDataHandler.sharedChecked()
            var deviceId = launchAppIntent?.device.udn
            if deviceId == nil {
                 deviceId = await appLinkActor.requestPrimaryDevice()?.id
            }

            guard let deviceId else {
                throw IntentError.noSavedDevices
            }

            return await appLinkActor.requestDeviceApps(deviceId: deviceId)
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        if let iconURL {
            DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(url: iconURL))
        } else {
            DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: "app.dashed"))
        }
    }
}

#if !os(watchOS)
import CoreSpotlight

extension  AppLink: IndexedEntity {}
#endif
