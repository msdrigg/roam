import AppIntents
import Foundation
import os

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct OpenDeviceIntent: OpenIntent {
    public typealias Value = DeviceAppEntity

    public init() {}
    public static let title: LocalizedStringResource = LocalizedStringResource("Open a device", comment: "Configuration title for a settings page")

    public static let openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    public var target: DeviceAppEntity

    @MainActor
    public func perform() async throws -> some IntentResult {
        await DataHandler(modelContainer: getSharedModelContainer()).setSelectedDevice(target.modelId)
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
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
    public var device: DeviceAppEntity?

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

    public var selectedDevice: DeviceAppEntity? {
        if !manuallySelectDevice {
            return nil
        }

        return device
    }
}

#if os(iOS)
@available(iOS 18.0, *)
extension DeviceChoiceIntent: ControlConfigurationIntent {}
#endif

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
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
    public var device: DeviceAppEntity?

    @Parameter(title: LocalizedStringResource("Manually select which apps to show", comment: "Configuration field title controlling whether or not apps are manually selected"), default: false)
    public var manuallySelectApps: Bool

    @Parameter(title: LocalizedStringResource("App 1", comment: "Configuration field title for selecting the first app"))
    public var app1: AppLinkAppEntity?

    @Parameter(title: LocalizedStringResource("App 2", comment: "Configuration field title for selecting the second app"))
    public var app2: AppLinkAppEntity?

    @Parameter(title: LocalizedStringResource("App 3", comment: "Configuration field title for selecting the third app"))
    public var app3: AppLinkAppEntity?

    #if !os(watchOS)
    @Parameter(title: LocalizedStringResource("App 4", comment: "Configuration field title for selecting the fourth app"))
    public var app4: AppLinkAppEntity?
    #endif

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
                    #if !os(watchOS)
                    \.$app4
                    #endif
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
#if !os(watchOS)
                    \.$app4
                    #endif
                }
            } otherwise: {
                Summary {
                    \.$manuallySelectDevice
                    \.$manuallySelectApps
                }
            }
        }
    }

    public var selectedDevice: DeviceAppEntity? {
        if !manuallySelectDevice {
            return nil
        }

        return device
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
public struct ButtonPressIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent {
    public static let intentClassName = "ButtonPressIntent"

    public static let title: LocalizedStringResource = LocalizedStringResource("Press a button", comment: "Configuration title for a button press action")
    public static let description = IntentDescription(LocalizedStringResource("Press a button on the connected device", comment: "Configuration description for a button press action"))

    public init() {}

    @Parameter(title: LocalizedStringResource("Device", comment: "Configuration field title for a device selection field"))
    var device: DeviceAppEntity?

    @Parameter(title: LocalizedStringResource("Button", comment: "Configuration field title for a button selection field"))
    var button: RemoteButtonAppEnum

    public static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$button) on \(\.$device)")
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$button, \.$device)) { button, device in
            DisplayRepresentation(
                title: LocalizedStringResource("Press \(button) on \(device!)", comment: "Title for a shortcut action")
            )
        }
    }

    public init(_ button: RemoteButton, device: DeviceAppEntity?) {
        self.button = button.buttonAppEnum
        self.device = device
    }

    public func perform() async throws -> some IntentResult {
        Log.userInteraction.debug(
            "Pressing widget button \(button.button.apiValue ?? "nil") on device \(device?.name ?? "nil")"
        )

        try await clickButton(button: button.button, device: device)

        return .result()
    }
}

#if WIDGET
public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
    Log.userInteraction.notice("Pressing widget button \(button.apiValue ?? "nil", privacy: .public) on device \(device?.name ?? "nil", privacy: .public)")
    let modelContainer = await getSharedModelContainer()

    let dataHandler = DataHandler(modelContainer: modelContainer)

    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
    }

    guard let targetDevice else {
        Log.userInteraction.warning("Trying to press button with no device available")
        throw IntentError.noSavedDevices
    }

    #if os(watchOS)
    if let deviceKey = button.apiValue {
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
    #else
    do {
        try await withTimeout(delay: 5) {
            do {
                guard let url = URL(string: targetDevice.location) else {
                    throw IntentError.deviceNotConnectable
                }
                try await ECPWebsocketClient(location: url).oneOff { session in
                    try await session.pressButton(button)
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

public func launchApp(app: AppLinkAppEntity, device: DeviceAppEntity?) async throws {
    let modelContainer = await getSharedModelContainer()
    let dataHandler = DataHandler(modelContainer: modelContainer)

    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
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
#else
public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
    throw APIError.wrongContext("Shouldn't be called outside of widget context")
}
public func launchApp(app: AppLinkAppEntity, device: DeviceAppEntity?) async throws {
    throw APIError.wrongContext("Shouldn't be called outside of widget context")
}
#endif

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

extension AppLinkAppEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("TV App", comment: "TV App Selection option"))
    public static let defaultQuery = AppLinkAppEntityQuery()

    public struct AppLinkAppEntityQuery: EntityQuery {
        @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent

        public init() {}

        public func entities(for identifiers: [AppLinkAppEntity.ID]) async throws -> [AppLinkAppEntity] {
            let appLinkActor = DataHandler(modelContainer: await getSharedModelContainer())
            return try await appLinkActor.appEntities(for: identifiers, deviceUid: launchAppIntent?.device.udn)
        }

        func entities(matching string: String) async throws -> [AppLinkAppEntity] {
            let appLinkActor = DataHandler(modelContainer: await getSharedModelContainer())
            return try await appLinkActor.appEntities(matching: string, deviceUid: launchAppIntent?.device.udn)
        }

        public func suggestedEntities() async throws -> [AppLinkAppEntity] {
            let appLinkActor = DataHandler(modelContainer: await getSharedModelContainer())
            return try await appLinkActor.appEntities(deviceUid: launchAppIntent?.device.udn)
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: (icon != nil) ? DisplayRepresentation.Image(data: icon!) : DisplayRepresentation.Image(systemName: "app.dashed"))
    }
}

#if !os(watchOS)
import CoreSpotlight

extension AppLinkAppEntity: IndexedEntity {}
#endif
