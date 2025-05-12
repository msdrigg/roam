import AppIntents
import AVFoundation
import Intents
import os
import StoreKit
import SwiftData
import SwiftUI
import Foundation
import TipKit

#if os(iOS)
import WatchConnectivity
#endif

let globalToolbarShrinkWidth: CGFloat = 300

let globalMajorActions: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

@MainActor
private func unreadMessageFetchDescriptor() -> FetchDescriptor<Message> {
    return FetchDescriptor(predicate: globalUnviewedMessagePredicate)
}

enum KeyboardFocus {
    case entry
    case monitor
}

struct RemoteViewContained: View {
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Query(deviceFetchDescriptor()) private var devices: [Device]
    @Query(unreadMessageFetchDescriptor()) private var unreadMessages: [Message]
    @Environment(\.dismiss) var dismiss

    @State private var scanningActor: DeviceDiscoveryActor?
    @State private var ssdpActor: DeviceDiscoveryActor?
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntryManual: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    @AppStorage(UserDefaultKeys.localNetworkPermissionGranted) private var networkPermissionGranted: Bool = false
    @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

    private var networkMonitor: NetworkMonitor {
        self.appDelegate.networkMonitor
    }

    private var isInMenuBar: Bool

    private var ecpSessionState: ECPMonitor {
        appDelegate.ecpMonitor
    }

    private var ecpSession: ECPWebsocketClient? {
        appDelegate.ecpMonitor.ecpClient
    }

    #if os(macOS)
    private var showKeyboardEntry: Bool {
        return false
    }
    #else
    private var showKeyboardEntry: Bool {
        return showKeyboardEntryManual
    }
    #endif

    init(isInMenuBar: Bool = false) {
        self.isInMenuBar = isInMenuBar
    }

    var headphonesModeDisabled: Bool {
        !(selectedDevice?.supportsDatagram ?? true)
    }

    var hideUIForKeyboardEntry: Bool {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom  == .pad {
            return false
        } else {
            return showKeyboardEntry
        }
#else
        return false
#endif
    }

    var hideAppsForKeyboardEntry: Bool {
#if os(iOS)
        return showKeyboardEntry
#else
        return false
#endif
    }

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var shouldScanIPRangeAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true

    var scanSSDP: Bool {
        shouldScanIPRangeAutomatically
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass

    @FocusState var focusKeyboardMonitor: KeyboardFocus?

    private var appLinkRows: Int {
        #if os(macOS)
            return 2
        #else
            if verticalSizeClass == .compact {
                return 1
            } else {
                return 2
            }
        #endif
    }

    #if os(iOS)
        @State var windowScene: UIWindowScene?
    #endif

    private var selectedDevice: Device? {
        if let manuallySelectedDevice, manuallySelectedDevice.visible {
            manuallySelectedDevice
        } else {
            devices.filter{
                $0.visible
            }.min { d1, d2 in
                (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
            }
        }
    }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State var controlledIsHorizontal: Bool?
    @AppStorage(UserDefaultKeys.macosKeysWindowHorizontal) private var windowWasLastHorizontal: Bool = false

    var isHorizontal: Bool {
        if let controlledIsHorizontal {
            return controlledIsHorizontal
        }
        #if os(macOS) || os(visionOS)
        return windowWasLastHorizontal
        #else
        return UIDevice.current.orientation.isLandscape
        #endif
    }

    @State var volume: Float = 0
    @State var lastVolumeChangeFromTv: Bool = false

    @ScaledMetric var buttonRadius = globalButtonRadius

    private struct IsHorizontalKey: PreferenceKey {
        static let defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    @Namespace var animation

    @Environment(\.uuidUpdater) private var updater

    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }

    var body: some View {
        if runningInPreview {
            remotePage
        } else {
            remotePage
                .task {
                    // Hack to make sure we don't get ina badk focus state :/
                    focusKeyboardMonitor = .monitor
                    while !Task.isCancelled {
                        try? await Task.sleep(duration: 1)

                        if !showKeyboardEntry {
                            focusKeyboardMonitor = .monitor
                        }
                    }
                }
                .defaultFocus($focusKeyboardMonitor, .monitor, priority: .userInitiated)
                .onChange(of: focusKeyboardMonitor) {
                    if focusKeyboardMonitor == nil && !showKeyboardEntry {
                        focusKeyboardMonitor = .monitor
                    }
                    if !showKeyboardEntry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if !showKeyboardEntry {
                                focusKeyboardMonitor = .monitor
                            }
                        }
                    }
                }
                .onChange(of: ecpSessionState.textEditStatus) { old, new in
                    if old.isActive && !new.isActive {
                        withAnimation {
                            showKeyboardEntryManual = false
                        }
                    } else if !old.isActive && new.isActive {
                        withAnimation {
                            showKeyboardEntryManual = true
                        }
                    }
                }
                .onChange(of: showKeyboardEntry) {
                    if !showKeyboardEntry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if !showKeyboardEntry {
                                focusKeyboardMonitor = .monitor
                            }
                        }
                    }
                }
                .task {
                    // Configure and load your tips at app launch.
                    try? Tips.configure([
                        .displayFrequency(.immediate),
                        .datastoreLocation(.groupContainer(identifier: tipsAppGroup))
                    ])
                }
                .task {
                    while !Task.isCancelled {
                        await MessageDataHandler.shared.refreshMessagesIfExpectingNewMessages()
                        try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000 * 3600)
                    }
                }
                .task {
                    if loadTestingData() {
                        // swiftlint:disable:next force_try
                        try! await RoamDataHandler().loadTestData()
                        // try! await RoamDataHandler().loadLoadTestData()
                    } else if usingTestingDataContainer() {
                        // swiftlint:disable:next force_try
                        try! await RoamDataHandler().clearData()
                    }
                }
#if os(iOS)
                .task(id: devices.count, priority: .background) {
                    // Send devices to connected watch
                    WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices.map { $0.toAppEntity() })

                    for await _ in AsyncTimerSequence.repeating(every: .seconds(60 * 10)) {
                        WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices.map { $0.toAppEntity() })
                    }
                }
#endif
#if !os(macOS)
            .onAppear {
                appDelegate.navigationPath.focusedWindow = .remote
            }
#endif
                .task {
                    do {
                        Log.network.notice("\("Checking", privacy: .public) for local network permission")
                        let permission = try await requestLocalNetworkAuthorization()
                        Log.network.notice("Got permission check result \(permission, privacy: .public)")
                        self.networkPermissionGranted = permission
                    } catch {
                        Log.network.error("Error requesting local network authorization \(error, privacy: .public)")
                    }
                }
                .onAppear {
                    Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
                }
                .onDisappear {
                    Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
                }
                .task(id: "\(ssdpActor != nil && scanSSDP)", priority: .background) {
                    if scanSSDP {
                        await ssdpActor?.scanSSDPContinually()
                    }
                }
                .task(id: "\(scanningActor != nil && selectedDevice == nil && scanSSDP)-\(networkMonitor.networkConnection)") {
                    if scanSSDP && selectedDevice == nil {
                        await scanningActor?.scanIPV4Once()
                    }
                }
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    for await _ in exponentialBackoff(min: 30, max: 3600) {
                        if let selectedDevice, let ecpSession {
                            Log.connection
                                .info("Refreshing device \(selectedDevice.location, privacy: .public) after backoff")
                            if Task.isCancelled {
                                return
                            }
                            let handler = RoamDataHandler()
                            await handler.refreshDevice(
                                client: ECPWebsocketRefreshClient(
                                    id: selectedDevice.persistentModelID,
                                    client: ecpSession,
                                    location: selectedDevice.location
                                )
                            )
                        } else {
                            Log.connection
                                .info("No selected device to refresh")
                            return
                        }
                    }
                }
                .task(id: selectedDevice?.location, priority: .medium) {
                    Log.connection.notice("Creating ecp session with location \(String(describing: selectedDevice?.location), privacy: .public)")
                    if let device = selectedDevice?.toAppEntity() {
                        self.ecpSessionState.setDevice(device)
                    } else {
                        self.ecpSessionState.setDevice(nil)
                    }
                }
                .task(id: "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")") {
                    if !headphonesModeEnabled {
                        #if os(iOS)
                        do {
                        try AVAudioSession.sharedInstance().setCategory(.ambient)
                        try AVAudioSession.sharedInstance().setActive(false)
                        } catch {
                            Log.headphones.notice("Unable to set AVAudioSession category to background: \(#fileID, privacy: .public)")
                        }
                        #endif
                        return
                    }
                    defer {
                        headphonesModeEnabled = false
                    }

                    if let device = selectedDevice, let ecpSession {
                        let location = device.location
                        let rtcpPort = device.rtcpPort
                        do {
                            try await listenContinually(
                                ecpSession: ecpSession,
                                location: location,
                                rtcpPort: rtcpPort
                            )
                            Log.headphones.notice(
                                "Listencontinually returned \(#fileID, privacy: .public)"
                            )
                        } catch {
                            Log.headphones.warning("Catching error in pl handler \(error, privacy: .public)")
                            // Increment errorTrigger if the error is anything but a cancellation error
                            if !(error is CancellationError) {
                                Log.headphones.notice("Non-cancellation error in PL \(#fileID, privacy: .public)")
                                errorTrigger += 1
                            }
                        }
                    }
                }
                .onAppear {
                    scanningActor = DeviceDiscoveryActor(updater: {
                        updater?.update()
                    })
                    ssdpActor = DeviceDiscoveryActor(updater: {
                        updater?.update()
                    })
                }
                #if os(macOS)
                .onKeyDown({ key in pressKey(key.key, modifiers: key.modifiers) }, enabled: true)
                .onWindowFocused {
                    Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")
                    appDelegate.navigationPath.focusedWindow = .remote
                }
                #endif
                .onChange(of: focusKeyboardMonitor) {
                    if focusKeyboardMonitor == nil && !showKeyboardEntry {
                        focusKeyboardMonitor = .monitor
                    }
                    if !showKeyboardEntry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if !showKeyboardEntry {
                                focusKeyboardMonitor = .monitor
                            }
                        }
                    }
                }
                .onChange(of: showKeyboardEntry) {
                    if !showKeyboardEntry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if !showKeyboardEntry {
                                focusKeyboardMonitor = .monitor
                            }
                        }
                    }
                }

        }
    }

    var remotePage: some View {
        ZStack {
            Color.clear
                .overlay(
                    GeometryReader { proxy in
                        let isHorizontal = proxy.size.width > proxy.size.height

                        Color.clear.preference(key: IsHorizontalKey.self, value: isHorizontal)
                    }
                )
                .onPreferenceChange(IsHorizontalKey.self) { value in
                    DispatchQueue.main.async {
                        withAnimation {
                            Log.userInteraction.notice("IsHorizontalKey changed to \(value, privacy: .public)")
                            controlledIsHorizontal = value
                            windowWasLastHorizontal = value
                        }
                    }
                }

            HStack {
                Spacer()
                VStack(alignment: .center, spacing: 0) {
                    #if os(macOS)
                    HStack(alignment: .center) {
                        Spacer()

                        DevicePicker(
                            devices: devices,
                            device: Binding(get: {
                                selectedDevice
                            }, set: {
                                manuallySelectedDevice = $0
                            }),
                            ecpSessionState: ecpSessionState,
                            showScanning: true
                        )
                        .accessibilityIdentifier("DevicePickerTop")
                        .buttonStyle(PaddedBorderlessButtonStyleWithChevron())
                        .menuStyle(.button)
                        .controlSize(.extraLarge)
                        .glowing(enabled: selectedDevice == nil)
                        .hoverHighlight(enabled: selectedDevice != nil)

                        if isInMenuBar {
                            Button(action: {
                                openWindow(id: "remote")
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    NSApp.forceFront("remote")
                                }
                            }, label: {
                                Label("Open main window", systemImage: "macwindow.on.rectangle")
                                    .labelStyle(.iconOnly)
                            })
                            .buttonStyle(PaddedBorderlessButtonStyle())
                            .menuStyle(.button)
                            .controlSize(.extraLarge)
                            .hoverHighlight(enabled: true)
                        }

                        Spacer()
                    }
                    #elseif os(visionOS)
                    HStack(alignment: .center) {
                        Button(action: {
                            keyboardLeaving = showKeyboardEntry
                            withAnimation {
                                showKeyboardEntryManual = !showKeyboardEntry
                            }
                        }, label: {
                            Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
                        })
                        .accessibilityIdentifier("KeyboardButton")
                        .focusable(true, interactions: [.activate, .edit])
                        .focused($focusKeyboardMonitor, equals: .monitor)
                        .onKeyPress { ke in
                            for shortcut in allKeyboardShortcuts {
                                if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                                    let title = shortcut.title
                                    Log.headphones.notice("Not handling key press because found shortcut with title \(title, privacy: .public)")
                                    if let rb = title.matchingRemoteButton {
                                        pressButton(rb)
                                        return .handled
                                    }

                                    if title == .chatWithDeveloper {
                                        appDelegate.navigationPath.append(.messageDestination)
                                    } else
                                    if title == .keyboardShortcuts {
                                        appDelegate.navigationPath.append(.keyboardShortcutDestinaion)
                                    } else {
                                        Log.userInteraction.warning("Unknown function for keyboard shortcut \(title, privacy: .public)")
                                    }

                                    return .handled
                                }
                            }

                            pressKey(ke.key, modifiers: ke.modifiers)
                            return .handled
                        }
                        .controlSize(.large)
                        .font(.headline)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(selectedDevice == nil)

                        Spacer()

                        DevicePicker(
                            devices: devices,
                            device: Binding(get: {
                                selectedDevice
                            }, set: {
                                manuallySelectedDevice = $0
                            }),
                            ecpSessionState: ecpSessionState,
                            showScanning: true
                        )
                        .accessibilityIdentifier("DevicePickerCenter")
                        .buttonStyle(PaddedBorderlessButtonStyle())
                        .menuStyle(.button)
                        .controlSize(.extraLarge)
                        .hoverEffect(.highlight)
                        .cornerRadius(buttonRadius)
                        .glowing(enabled: selectedDevice == nil)
                    }
                    #elseif os(iOS)
                    if selectedDevice == nil {
                        HStack(alignment: .center) {
                            Spacer()

                            DevicePicker(
                                devices: devices,
                                device: Binding(get: {
                                    selectedDevice
                                }, set: {
                                    manuallySelectedDevice = $0
                                }),
                                ecpSessionState: ecpSessionState,
                                showScanning: true
                            )
                            .accessibilityIdentifier("DevicePickerCenter")
                            .buttonStyle(PaddedBorderlessButtonStyle())
                            .glowing(enabled: selectedDevice == nil)

                            Spacer()
                        }
                        .offset(y: -20)
                    }
                    #endif

                    if selectedDevice == nil {
                        Button(String(localized: "Add a device manually", comment: "Label on a button to add a device"), systemImage: "plus") {
                            appDelegate.navigationPath.showAddDevice = true
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.body)
#if os(iOS)
                        .offset(y: -20)
                        .buttonStyle(.bordered)
                        .foregroundStyle(Color.accentColor)
#else
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.secondary)
#endif
                        .customKeyboardShortcut(.addDevice)
                    }

                    if isHorizontal {
                        horizontalBody()
                            .disabled(selectedDevice == nil)
                            .font(.title2)
                            .fontDesign(.rounded)
                            .controlSize(.extraLarge)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle)
                            .labelStyle(.iconOnly)
                    } else {
                        verticalBody()
                            .disabled(selectedDevice == nil)
                            .font(.title2)
                            .fontDesign(.rounded)
                            .controlSize(.extraLarge)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle)
                            .labelStyle(.iconOnly)
                    }

                    if !hideUIForKeyboardEntry {
                        if unreadMessages.count > 0 {
                            // swiftlint:disable:next line_length
                            NotificationBanner(message: String(localized: "The developer chatted you back", comment: "Notification indicator that there was is message response waiting to be read"), onClick: {
#if os(macOS)
                                openWindow(id: "messages")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    NSApp.forceFront("messages")
                                }
#else
                                appDelegate.navigationPath.append(NavigationDestination.messageDestination)
#endif
                            }, level: .info)
                        }
                        NetworkConnectivityBanner()
                    }

#if !os(macOS)
                    if showKeyboardEntry {
                        Spacer()
                    }
#endif
                }
                .frame(maxHeight: .infinity)
                Spacer()
            }
            .frame(maxHeight: .infinity)
            #if !os(macOS)
            .overlay {
                #if os(iOS)
                    if controlVolumeWithHWButtons && !headphonesModeEnabled {
                        CustomVolumeSliderOverlay(volume: $volume) { volumeEvent in
                            let key: RemoteButton = switch volumeEvent.direction {
                            case .up:
                                .volumeUp
                            case .down:
                                .volumeDown
                            }
                            Log.connection.notice(
                                "Pressing button \(String(describing: key), privacy: .public) with volume \(volume, privacy: .public) after volume event \(String(describing: volumeEvent), privacy: .public)"
                            )
                            pressButton(key)
                        }
                            .id("VolumeOverlay")
                            .frame(maxWidth: 1)
                    }
                #endif

                if showKeyboardEntry {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack {
                                Button(action: {
                                    keyboardLeaving = true
                                    withAnimation {
                                        showKeyboardEntryManual = false
                                    }
                                }, label: {
                                    ZStack {
                                        Rectangle().foregroundColor(.clear)
                                        VStack {
                                            Spacer()
                                        }
                                    }.contentShape(Rectangle())
                                })
                                .frame(maxHeight: .infinity)
                                .buttonStyle(.plain)

                                KeyboardEntry(
                                    showing: Binding<Bool>(get: {
                                        showKeyboardEntry
                                    }, set: { newVal in
                                        showKeyboardEntryManual = newVal
                                    }),
                                    onKeyPress: { char async in
                                        await self.pressKeyAsync(char, modifiers: EventModifiers())
                                    },
                                    leaving: keyboardLeaving
                                )
                                .focused($focusKeyboardMonitor, equals: .entry)
                                .padding(.bottom, 10)
                                .padding(.horizontal, 10)
                                .zIndex(1)
                            }.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        }
                        .scrollIndicators(.never)
                        #if !os(visionOS)
                            .scrollDismissesKeyboard(.immediately)
                        #endif
                    }
                }
            }
            #endif
            .padding(.horizontal, 20)
#if os(macOS) || os(visionOS)
            .applyBuilder {
                if #available(macOS 15.0, *) {
                    $0
                        .padding(.top, 10)
                } else {
                    $0
                        .padding(.top, 20)
                }
            }
#else
            .padding(.top, 20)
#endif
            .padding(.bottom, 10)
#if !os(visionOS) && !os(macOS)
            .toolbar(id: "remote") {
                ToolbarItem(id: "keyboard", placement: .topBarLeading) {
                    Button(action: {
                        keyboardLeaving = showKeyboardEntry
                        withAnimation {
                            showKeyboardEntryManual = !showKeyboardEntry
                        }
                    }, label: {
                        Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
                    })
                    .accessibilityIdentifier("KeyboardButton")
                    .focusable(true, interactions: [.activate, .edit])
                    .focused($focusKeyboardMonitor, equals: .monitor)
                    .onKeyPress { ke in
                        for shortcut in allKeyboardShortcuts {
                            if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                                let title = shortcut.title
                                Log.userInteraction.notice("Not handling key press because found shortcut with title \(title, privacy: .public)")
                                if let rb = title.matchingRemoteButton {
                                    pressButton(rb)
                                    return .handled
                                }

                                if title == .chatWithDeveloper{
                                    appDelegate.navigationPath.append(.messageDestination)
                                } else if title == .keyboardShortcuts {
                                    appDelegate.navigationPath.append(.keyboardShortcutDestinaion)
                                } else if title == .copy {
                                    if let text = ecpSessionState.textEditStatus.text {
                                        UIPasteboard.general.string = text
                                    }
                                } else if title == .cut {
                                    if let text = ecpSessionState.textEditStatus.text {
                                        UIPasteboard.general.string = text
                                    }

                                    if let id = ecpSessionState.textEditStatus.texteditId {
                                        Task {
                                            do {
                                                try await ecpSession?.setTextEdit("", texteditId: id)
                                            } catch {
                                                Log.userInteraction.error("Error cutting text: \(error, privacy: .public)")
                                            }
                                        }
                                    }
                                } else if title == .paste {
                                    Log.userInteraction.notice("Trying to paste: \(#fileID, privacy: .public)")
                                    if let id = ecpSessionState.textEditStatus.texteditId, UIPasteboard.general.hasStrings {
                                        if let text = UIPasteboard.general.string {
                                            Log.userInteraction.notice("Trying to paste \(text, privacy: .public)")
                                            Task {
                                                do {
                                                    try await ecpSession?.setTextEdit(text, texteditId: id)
                                                } catch {
                                                    Log.userInteraction.error("Error cutting text: \(error, privacy: .public)")
                                                }
                                            }
                                        } else {
                                            Log.userInteraction.warning("No text to paste: \(#fileID, privacy: .public)")
                                        }
                                    } else {
                                        Log.userInteraction.notice("Not pasting due to empty textedit id (\(ecpSessionState.textEditStatus.texteditId ?? "none", privacy: .public)) or false UI pasteboard hasStrings (\(UIPasteboard.general.hasStrings), privacy: .public)")
                                    }
                                } else {
                                    Log.userInteraction.warning("Unknown function for keyboard shortcut \(title, privacy: .public)")
                                }

                                return .handled
                            }
                        }

                        pressKey(ke.key, modifiers: ke.modifiers)
                        return .handled
                    }
                    .controlSize(.large)
                    .font(.headline)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(selectedDevice == nil)
                    .font(.headline)
                }
            ToolbarItem(id: "device-picker", placement: .topBarTrailing) {
                    DevicePicker(
                        devices: devices,
                        device: Binding(get: {
                            selectedDevice
                        }, set: {
                            manuallySelectedDevice = $0
                        }),
                        ecpSessionState: ecpSessionState
                    )
                    .accessibilityIdentifier("DevicePickerTop")
                    .buttonStyle(.plain)
                    .frame(idealWidth: 100, maxWidth: 350)
                    .disabled(selectedDevice == nil)
                }
            }
#endif
#if !os(visionOS)
                .sensoryFeedback(.error, trigger: errorTrigger)
#endif
        }
        .sheet(isPresented: appDelegate.navigationPath.showingAddDevice(for: .remote)) {
            AddDeviceFlow()
        }
        .defaultFocus($focusKeyboardMonitor, .monitor, priority: .userInitiated)
    }

    func horizontalBody() -> some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: globalButtonSpacing * 2) {
                if !hideUIForKeyboardEntry {
                    Spacer()
                    VStack {
#if !os(macOS)
                        Spacer().frame(maxHeight: 100)
#endif
                        // Center Controller with directional buttons
                        CenterController(pressCounter: buttonPressCount, action: pressButton)
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "centerController", in: animation)
#if !os(macOS)
                        Spacer().frame(maxHeight: 100)
#endif
                    }
                    #if os(macOS)
                    .focusSection()
                    #endif
                }
                Spacer()

                VStack(alignment: .center) {

                    // Row with Back and Home buttons
                    TopBar(pressCounter: buttonPressCount, action: pressButton)
                        .matchedGeometryEffect(id: "topBar", in: animation)
                    #if os(macOS)
                        .focusSection()
                    #endif

                    if !hideUIForKeyboardEntry {
#if !os(macOS)
                        Spacer().frame(maxHeight: 60)
#endif

                        // Grid of 9 buttons
                        ButtonGrid(
                            pressCounter: buttonPressCount,
                            action: pressButton,
                            enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                            disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                        )
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "buttonGrid", in: animation)
#if os(macOS)
                .focusSection()
#endif
                    }
                }
                #if os(macOS)
                .focusSection()
                #endif
                Spacer()
            }
            #if os(macOS)
            .focusSection()
            #endif
            .frame(maxWidth: 600)

            if !hideAppsForKeyboardEntry && selectedDevice != nil {
                Spacer()
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if !os(visionOS)
                .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif
            } else {
                Spacer()
            }
#if os(macOS)
            Spacer()
#endif

            Spacer()
        }
    }

    func verticalBody() -> some View {
        VStack(alignment: .center, spacing: 0) {
            #if os(macOS)
                Spacer()
            #elseif os(visionOS)
                Spacer()
                    .frame(maxHeight: 30)
            #endif

            // Row with Back and Home buttons
            TopBar(pressCounter: buttonPressCount, action: pressButton)
                .matchedGeometryEffect(id: "topBar", in: animation)

            Spacer()

            // Center Controller with directional buttons
            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "centerController", in: animation)

            if !hideUIForKeyboardEntry {
                Spacer()
                // Grid of 9 buttons
                ButtonGrid(
                    pressCounter: buttonPressCount,
                    action: pressButton,
                    enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                    disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                )
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "buttonGrid", in: animation)
            }

            if !hideAppsForKeyboardEntry && selectedDevice != nil {
                Spacer()
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if !os(visionOS)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif
            } else {
                Spacer()
            }
#if os(macOS)
            Spacer()
#endif
            Spacer()
        }
    }

    func shouldRequestReview() -> Bool {
        let userActionCount = UserDefaults.standard.integer(forKey: UserDefaultKeys.userMajorActionCount)
        let lastVersionAsked = UserDefaults.standard.string(forKey: UserDefaultKeys.appVersionAtLastReviewRequest)
        let lastDateAsked = UserDefaults.standard.object(forKey: UserDefaultKeys.dateOfLastReviewRequest) as? Date

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else {
            return false
        }

        if userActionCount < 10 {
            return false
        }

        if currentVersion == lastVersionAsked {
            return false
        }

        if let lastDate = lastDateAsked, Calendar.current.date(byAdding: .month, value: 1, to: lastDate)! > Date() {
            return false
        }

        return true
    }

    func incrementButtonPressCount(_ key: RemoteButton) {
        buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
    }

    func donateButtonIntent(_ key: RemoteButton) {
        switch key {
        case .power:
            let intent = PowerIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        case .select:
            let intent = OkIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        case .mute:
            let intent = MuteIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        case .volumeUp:
            let intent = VolumeUpIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        case .volumeDown:
            let intent = VolumeDownIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        case .playPause:
            let intent = PlayIntent()
            intent.device = selectedDevice?.toAppEntity()
            intent.donate()
        default:
            return
        }
    }

    func donateAppLaunchIntent(_ link: AppLinkAppEntity) {
        let intent = LaunchAppIntent()
        intent.app = link
        intent.device = selectedDevice?.toAppEntity()
        intent.donate()
    }

    func launchApp(_ app: AppLinkAppEntity) {
        donateAppLaunchIntent(app)
        incrementButtonPressCount(.inputAV1)
        Task.detached {
            do {
                try await ecpSession?.launchApp(app.id)
            } catch {
                Log.connection.error("Error opening app \(app.id, privacy: .public): \(error, privacy: .public)")
            }
        }
        Task.detached {
            if let modelId = app.modelId {
                await RoamDataHandler().setSelectedApp(modelId)
            }
        }
    }

    func pressButton(_ button: RemoteButton) {
        incrementButtonPressCount(button)
        if globalMajorActions.contains(button) {
            handleMajorUserAction()
        }
        donateButtonIntent(button)
        if button == .headphonesMode {
            headphonesModeEnabled.toggle()
            return
        }

        Task {
            do {
                try await ecpSession?.pressButton(button)
            } catch {
                Log.connection.notice("Error sending button to device via ecp: \(error, privacy: .public)")
            }
        }
    }

    func pressKeyAsync(_ key: KeyEquivalent, modifiers: EventModifiers) async {
        let character = key.character
        Log.userInteraction.debug("Getting keyboard press \(character, privacy: .public)")
        if let button = RemoteButton.fromCharacter(character: character) {
            incrementButtonPressCount(button)
            if globalMajorActions.contains(button) {
                handleMajorUserAction()
            }
            donateButtonIntent(button)
        }

        if let ecpSession {
            Log.connection.notice("Getting ecp session to send data to: \(true)")
            do {
                try await ecpSession.pressCharacter(getModifiedCharacter(key, modifiers: modifiers))
            } catch {
                Log.connection.error("Error pressing character \(key.character, privacy: .public) on device \(error, privacy: .public)")
            }
        }
    }

    func pressKey(_ key: KeyEquivalent, modifiers: EventModifiers) {
        Task {
            await pressKeyAsync(key, modifiers: modifiers)
        }
    }

    func handleMajorUserAction() {
        // Increment user action count
        var count = UserDefaults.standard.integer(forKey: UserDefaultKeys.userMajorActionCount)
        count += 1
        UserDefaults.standard.set(count, forKey: UserDefaultKeys.userMajorActionCount)

        if shouldRequestReview() {
            #if os(iOS)
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
            #endif

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                #if os(iOS)
                    SKStoreReviewController.requestReview(in: windowScene)
                #elseif !os(visionOS)
                    SKStoreReviewController.requestReview()
                #endif
            }

            UserDefaults.standard.set(
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
                forKey: UserDefaultKeys.appVersionAtLastReviewRequest
            )
            UserDefaults.standard.set(Date(), forKey: UserDefaultKeys.dateOfLastReviewRequest)
        }
    }
}

#if DEBUG
#Preview(
    "Remote horizontal",
    traits: .fixedLayout(width: 400, height: 800)
) {
    RemoteView()
        .modelContainer(previewContainer)
        .environmentObject(RoamAppDelegate())
}
#endif
