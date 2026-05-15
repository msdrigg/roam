#if !os(macOS)
import AppIntents
import AVFoundation
import Intents
import os
import StoreKit
import SwiftUI
import Foundation

let globalToolbarShrinkWidth: CGFloat = 300

let globalMajorActions: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

enum KeyboardFocus {
    case entry
    case monitor
}

struct RemoteViewContained: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.requestReview) private var requestReview

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Environment(\.dismiss) var dismiss

    @State private var showKeyboardEntryManual: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var headphonesError: Error?
    @State private var errorTrigger: Int = 0
    @AppStorage(UserDefaultKeys.localNetworkPermissionGranted) private var networkPermissionGranted: Bool = false
    @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

    private let device: Device?
    private let unreadMessages: Int
    private let isInMenuBar: Bool
    private let externalShowKeyboard: Binding<Bool>?
    private let hidesKeyboardToolbarButton: Bool

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

    init(
        device: Device? = nil,
        unreadMessages: Int = 0,
        isInMenuBar: Bool = false,
        externalShowKeyboard: Binding<Bool>? = nil,
        hidesKeyboardToolbarButton: Bool = false
    ) {
        self.device = device
        self.unreadMessages = unreadMessages
        self.isInMenuBar = isInMenuBar
        self.externalShowKeyboard = externalShowKeyboard
        self.hidesKeyboardToolbarButton = hidesKeyboardToolbarButton
    }

    var headphonesModeDisabled: Bool {
        !(selectedDevice?.supportsDatagram ?? true)
    }

    var noVolumeControls: Bool {
        selectedDevice?.supportsAudioSettings == false
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
#if os(iOS) || os(visionOS)
        return showKeyboardEntry
#else
        return false
#endif
    }

    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true

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
        device
    }

    private var isDeviceOnline: Bool {
        selectedDevice?.isOnline() ?? false || inScreenshotTestingContext()
    }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State var controlledIsHorizontal: Bool?
    @AppStorage(UserDefaultKeys.macosKeysWindowHorizontal) private var windowWasLastHorizontal: Bool = false

    var isHorizontal: Bool {
        if let controlledIsHorizontal {
            #if os(macOS)
            return false
            #else
            return controlledIsHorizontal
            #endif
        }
        #if os(macOS)
        return false
        #elseif os(visionOS)
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

    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }

    private func keepFocusTask() async {
        focusKeyboardMonitor = .monitor
        while !Task.isCancelled {
            try? await Task.sleep(duration: 1)
            if !showKeyboardEntry {
                focusKeyboardMonitor = .monitor
            }
        }
    }

    private func restoreFocusIfNeeded() {
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

    private func handleTextEditStatusChange(old: TextEditStatus, new: TextEditStatus) {
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

    private func handleShowKeyboardChange() {
        if !showKeyboardEntry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !showKeyboardEntry {
                    focusKeyboardMonitor = .monitor
                }
            }
        }
    }

    private func networkPermissionTask() async {
        do {
            Log.network.notice("\("Checking", privacy: .public) for local network permission")
            let permission = try await requestLocalNetworkAuthorization()
            Log.network.notice("Got permission check result \(permission, privacy: .public)")
            self.networkPermissionGranted = permission
        } catch {
            Log.network.error("Error requesting local network authorization \(error, privacy: .public)")
        }
    }

    private func logAppear() {
        Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
    }

    private func logDisappear() {
        Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
    }

    private func refreshDeviceBackoffTask() async {
        for await _ in exponentialBackoff(min: 30, max: 3600) {
            if let selectedDevice, let ecpSession {
                Log.connection
                    .info("Refreshing device \(selectedDevice.location, privacy: .public) after backoff")
                if Task.isCancelled {
                    return
                }
                let handler = RoamDataHandler.shared
                await handler.refreshDevice(
                    client: ECPWebsocketRefreshClient(
                        id: selectedDevice.id,
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

    private func ecpSessionLocationTask() async {
        Log.connection.notice("Creating ecp session with location \(String(describing: selectedDevice?.location), privacy: .public)")
        if let device = selectedDevice {
            self.ecpSessionState.setDevice(device)
        } else {
            self.ecpSessionState.setDevice(nil)
        }
    }

    private func headphonesTask() async {
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
                if !(error is CancellationError) {
                    Log.headphones.notice("Non-cancellation error in PL \(#fileID, privacy: .public)")
                    errorTrigger += 1
                    headphonesError = error
                }
            }
        }
    }

    #if os(macOS)
    private func handleWindowFocused() {
        Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")
        appDelegate.navigationPath.focusedWindow = .remote
    }
    #endif

    private func syncExternalKeyboardOnAppear() {
        if let externalShowKeyboard,
           externalShowKeyboard.wrappedValue != showKeyboardEntryManual {
            showKeyboardEntryManual = externalShowKeyboard.wrappedValue
        }
    }

    private func propagateKeyboardManualChange(_ new: Bool) {
        if let externalShowKeyboard,
           externalShowKeyboard.wrappedValue != new {
            externalShowKeyboard.wrappedValue = new
        }
    }

    private func propagateExternalKeyboardChange(_ new: Bool?) {
        guard let new, showKeyboardEntryManual != new else { return }
        withAnimation {
            showKeyboardEntryManual = new
        }
    }

    private var headphonesTaskId: String {
        "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")"
    }

    var body: some View {
        if runningInPreview {
            remotePage
        } else {
            decoratedRemotePage
        }
    }

    private var decoratedRemotePage: some View {
        remotePage
            .task { await keepFocusTask() }
            .defaultFocus($focusKeyboardMonitor, .monitor, priority: .userInitiated)
            .onChange(of: focusKeyboardMonitor) { restoreFocusIfNeeded() }
            .onChange(of: ecpSessionState.textEditStatus) { old, new in
                handleTextEditStatusChange(old: old, new: new)
            }
            .onChange(of: showKeyboardEntry) { handleShowKeyboardChange() }
            .task { await networkPermissionTask() }
            .onAppear(perform: logAppear)
            .onDisappear(perform: logDisappear)
            .task(id: selectedDevice?.id, priority: .medium) { await refreshDeviceBackoffTask() }
            .task(id: selectedDevice?.location, priority: .medium) { await ecpSessionLocationTask() }
            .task(id: headphonesTaskId) { await headphonesTask() }
            #if os(macOS)
            .onKeyDown({ key in pressKey(key.key, modifiers: key.modifiers) }, enabled: true)
            .onWindowFocused(perform: handleWindowFocused)
            #endif
            .onChange(of: focusKeyboardMonitor) { restoreFocusIfNeeded() }
            .onChange(of: showKeyboardEntry) { handleShowKeyboardChange() }
            .onAppear(perform: syncExternalKeyboardOnAppear)
            .onChange(of: showKeyboardEntryManual) { _, new in
                propagateKeyboardManualChange(new)
            }
            .onChange(of: externalShowKeyboard?.wrappedValue) { _, new in
                propagateExternalKeyboardChange(new)
            }
    }

    private func toggleKeyboardEntry() {
        keyboardLeaving = showKeyboardEntry
        withAnimation {
            showKeyboardEntryManual = !showKeyboardEntry
        }
    }

    #if os(visionOS)
    private func handleVisionOSShortcutKeyPress(_ ke: KeyPress) -> KeyPress.Result {
        for shortcut in allKeyboardShortcuts {
            if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                let title = shortcut.title
                Log.headphones.notice("Not handling key press because found shortcut with title \(title, privacy: .public)")
                if let rb = title.matchingRemoteButton {
                    pressButton(rb)
                    return .handled
                }
                if title == .chatWithDeveloper {
                    appDelegate.navigationPath.openMessages()
                } else if title == .keyboardShortcuts {
                    appDelegate.navigationPath.openKeyboardShortcuts()
                } else {
                    Log.userInteraction.warning("Unknown function for keyboard shortcut \(title, privacy: .public)")
                }
                return .handled
            }
        }
        pressKey(ke.key, modifiers: ke.modifiers)
        return .handled
    }

    private var visionOSKeyboardHeader: some View {
        HStack(alignment: .center) {
            if !hidesKeyboardToolbarButton {
                Button(action: toggleKeyboardEntry, label: {
                    Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
                })
                .accessibilityIdentifier("KeyboardButton")
                .focusable(true, interactions: [.activate, .edit])
                .focused($focusKeyboardMonitor, equals: .monitor)
                .onKeyPress { ke in handleVisionOSShortcutKeyPress(ke) }
                .controlSize(.large)
                .font(.headline)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(selectedDevice == nil)
            }

            Spacer()

            deviceTitleHeader

            Spacer()
        }
        .padding(.bottom, 14)
    }
    #endif

    #if !os(visionOS) && !os(macOS)
    private var toolbarKeyboardButton: some View {
        Button(action: toggleKeyboardEntry, label: {
            Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
        })
        .accessibilityIdentifier("KeyboardButton")
        .focusable(true, interactions: [.activate, .edit])
        .focused($focusKeyboardMonitor, equals: .monitor)
        .onKeyPress { ke in handleToolbarKeyPress(ke) }
        .controlSize(.large)
        .font(.headline)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(selectedDevice == nil)
        .font(.headline)
    }

    private func handleToolbarPaste() {
        Log.userInteraction.notice("Trying to paste: \(#fileID, privacy: .public)")
        guard let id = ecpSessionState.textEditStatus.texteditId, UIPasteboard.general.hasStrings else {
            Log.userInteraction.notice("Not pasting due to empty textedit id (\(ecpSessionState.textEditStatus.texteditId ?? "none", privacy: .public)) or false UI pasteboard hasStrings (\(UIPasteboard.general.hasStrings), privacy: .public)")
            return
        }
        guard let text = UIPasteboard.general.string else {
            Log.userInteraction.warning("No text to paste: \(#fileID, privacy: .public)")
            return
        }
        Log.userInteraction.notice("Trying to paste \(text, privacy: .public)")
        Task {
            do {
                try await ecpSession?.setTextEdit(text, texteditId: id)
            } catch {
                Log.userInteraction.error("Error cutting text: \(error, privacy: .public)")
            }
        }
    }

    private func handleToolbarCut() {
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
    }

    private func handleToolbarKeyPress(_ ke: KeyPress) -> KeyPress.Result {
        for shortcut in allKeyboardShortcuts {
            if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                let title = shortcut.title
                Log.userInteraction.notice("Not handling key press because found shortcut with title \(title, privacy: .public)")
                if let rb = title.matchingRemoteButton {
                    pressButton(rb)
                    return .handled
                }
                if title == .chatWithDeveloper {
                    appDelegate.navigationPath.openMessages()
                } else if title == .keyboardShortcuts {
                    appDelegate.navigationPath.openKeyboardShortcuts()
                } else if title == .copy {
                    if let text = ecpSessionState.textEditStatus.text {
                        UIPasteboard.general.string = text
                    }
                } else if title == .cut {
                    handleToolbarCut()
                } else if title == .paste {
                    handleToolbarPaste()
                } else {
                    Log.userInteraction.warning("Unknown function for keyboard shortcut \(title, privacy: .public)")
                }
                return .handled
            }
        }
        pressKey(ke.key, modifiers: ke.modifiers)
        return .handled
    }
    #endif

    #if !os(macOS)
    #if os(iOS)
    private func handleVolumeEvent(_ volumeEvent: VolumeEvent) {
        let key: RemoteButton = switch volumeEvent.direction {
        case .up: .volumeUp
        case .down: .volumeDown
        }
        Log.connection.notice(
            "Pressing button \(String(describing: key), privacy: .public) with volume \(volume, privacy: .public) after volume event \(String(describing: volumeEvent), privacy: .public)"
        )
        pressButton(key)
    }

    @ViewBuilder
    private var volumeOverlay: some View {
        if controlVolumeWithHWButtons && !headphonesModeEnabled {
            CustomVolumeSliderOverlay(volume: $volume, changeVolume: handleVolumeEvent)
                .id("VolumeOverlay")
                .frame(maxWidth: 1)
        }
    }
    #endif

    private func dismissKeyboardEntry() {
        keyboardLeaving = true
        withAnimation {
            showKeyboardEntryManual = false
        }
    }

    private var keyboardEntryShowingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { showKeyboardEntry },
            set: { newVal in showKeyboardEntryManual = newVal }
        )
    }

    private func handleKeyboardEntryPress(_ char: KeyEquivalent) async {
        await self.pressKeyAsync(char, modifiers: EventModifiers())
    }

    @ViewBuilder
    private var keyboardEntryOverlay: some View {
        if showKeyboardEntry {
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Button(action: dismissKeyboardEntry, label: {
                            ZStack {
                                Rectangle().foregroundColor(.clear)
                                VStack {
                                    Spacer()
                                }
                            }
                            .contentShape(Rectangle())
                        })
                        .frame(maxHeight: .infinity)
                        .buttonStyle(.plain)

                        KeyboardEntry(
                            showing: keyboardEntryShowingBinding,
                            onKeyPress: handleKeyboardEntryPress,
                            leaving: keyboardLeaving
                        )
                        .focused($focusKeyboardMonitor, equals: .entry)
                        .padding(.bottom, 10)
                        .padding(.horizontal, 10)
                        .zIndex(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.never)
                #if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
                #endif
            }
        }
    }

    @ViewBuilder
    private var mobileOverlays: some View {
        #if os(iOS)
        volumeOverlay
        #endif
        keyboardEntryOverlay
    }
    #endif

    private func handleIsHorizontalChange(_ value: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                Log.userInteraction.notice("IsHorizontalKey changed to \(value, privacy: .public)")
                controlledIsHorizontal = value
                windowWasLastHorizontal = value
            }
        }
    }

    #if os(macOS)
    private func openMainWindowFromMenuBar() {
        openWindow(id: "main")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.forceFront("main")
        }
    }

    @ViewBuilder
    private var macOSTopHeader: some View {
        HStack(alignment: .center) {
            Spacer()

            DevicePicker(
                device: selectedDevice,
                ecpSessionState: ecpSessionState,
                showScanning: true
            )
            .buttonStyle(PaddedBorderlessButtonStyleWithChevron())
            .menuStyle(.button)
            .controlSize(.extraLarge)
            .glowing(enabled: selectedDevice == nil)
            .hoverHighlight(enabled: selectedDevice != nil)

            if isInMenuBar {
                Button(action: openMainWindowFromMenuBar, label: {
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
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private var iOSDeviceNameHeader: some View {
        if selectedDevice?.name != nil, !hideUIForKeyboardEntry {
            deviceTitleHeader
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)
        }
    }
    #endif

    @ViewBuilder
    private var deviceTitleHeader: some View {
        if let deviceName = selectedDevice?.name {
            HStack(spacing: 8) {
                Circle()
                    .fill(isDeviceOnline ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(deviceName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var topHeader: some View {
        #if os(macOS)
        macOSTopHeader
        #elseif os(iOS)
        iOSDeviceNameHeader
        #elseif os(visionOS)
        visionOSKeyboardHeader
        #endif
    }

    private func openMessages() {
#if os(macOS)
        openWindow(id: "messages")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.forceFront("messages")
        }
#else
        appDelegate.navigationPath.openMessages()
#endif
    }

    @ViewBuilder
    private var banners: some View {
        if !hideUIForKeyboardEntry {
            // Suppress the unread-developer-message banner under
            // screenshot tests — it's data-driven by an untrusted
            // count from the testing data fixture and clutters
            // marketing captures.
            if unreadMessages > 0 && !inScreenshotTestingContext() {
                // swiftlint:disable:next line_length
                NotificationBanner(message: String(localized: "The developer chatted you back", comment: "Notification indicator that there was is message response waiting to be read"), onClick: openMessages, level: .info)
            }
            NetworkConnectivityBanner()
        }
    }

    private var directionalBody: some View {
        Group {
            if isHorizontal {
                horizontalBody()
            } else {
                verticalBody()
            }
        }
        .disabled(selectedDevice == nil)
        .font(.title2)
        .fontDesign(.rounded)
        .controlSize(.extraLarge)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .labelStyle(.iconOnly)
    }

    private var isHorizontalDetector: some View {
        Color.clear
            .overlay(
                GeometryReader { proxy in
                    let isHorizontal = proxy.size.width > proxy.size.height
                    Color.clear.preference(key: IsHorizontalKey.self, value: isHorizontal)
                }
            )
            .onPreferenceChange(IsHorizontalKey.self) { value in
                handleIsHorizontalChange(value)
            }
    }

    private var mainColumn: some View {
        VStack(alignment: .center, spacing: 0) {
            topHeader
            directionalBody
            banners
#if !os(macOS)
            if showKeyboardEntry {
                Spacer()
            }
#endif
        }
    }

    var remotePage: some View {
        ZStack {
            isHorizontalDetector

            HStack(alignment: .top) {
                Spacer()
                mainColumn
                #if os(macOS)
                .fixedSize(horizontal: false, vertical: true)
                #else
                .frame(maxHeight: .infinity)
                #endif
                Spacer()
            }
            #if os(macOS)
            .frame(width: 225, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            #else
            .frame(maxHeight: .infinity)
            #endif
            #if !os(macOS)
            .overlay { mobileOverlays }
            #endif
            #if os(macOS)
            .padding(.horizontal, 6)
            #else
            .padding(.horizontal, 20)
            #endif
#if os(macOS) || os(visionOS)
            .applyBuilder {
                #if os(macOS)
                $0.padding(.top, 0)
                #else
                if #available(macOS 15.0, *) {
                    $0
                        .padding(.top, 10)
                } else {
                    $0
                        .padding(.top, 20)
                }
                #endif
            }
#else
            .padding(.top, 20)
#endif
            #if os(macOS)
            .padding(.bottom, 6)
            #elseif os(iOS)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .phone ? -32 : 10)
            #else
            .padding(.bottom, 10)
            #endif
#if !os(visionOS) && !os(macOS)
            .toolbar(id: "remote") {
                if !hidesKeyboardToolbarButton {
                    ToolbarItem(id: "keyboard", placement: .topBarLeading) {
                        toolbarKeyboardButton
                    }
                }
            }
#endif
#if !os(visionOS)
                .sensoryFeedback(.error, trigger: errorTrigger)
#endif
                .alertingError(message: "Headphones mode error", error: $headphonesError)
        }
        .customAccentColorTint()
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
                            disabled: Set([]),
                            noVolumeControls: noVolumeControls,
                            headphonesModeUnsupported: headphonesModeDisabled
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
        #if os(macOS)
        return VStack(alignment: .center, spacing: 30) {
            TopBar(pressCounter: buttonPressCount, action: pressButton)
                .matchedGeometryEffect(id: "topBar", in: animation)
                .focusSection()

            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "centerController", in: animation)
                .focusSection()

            if !hideUIForKeyboardEntry {
                ButtonGrid(
                    pressCounter: buttonPressCount,
                    action: pressButton,
                    enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                    disabled: Set([]),
                    noVolumeControls: noVolumeControls,
                    headphonesModeUnsupported: headphonesModeDisabled
                )
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "buttonGrid", in: animation)
                .focusSection()
            }

            if !hideAppsForKeyboardEntry && selectedDevice != nil {
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
            }
        }
        .fixedSize()
        #else
        VStack(alignment: .center, spacing: 0) {
            #if os(visionOS)
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
                    disabled: Set([]),
                    noVolumeControls: noVolumeControls,
                    headphonesModeUnsupported: headphonesModeDisabled
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
            Spacer()
        }
        #endif
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
            intent.device = selectedDevice
            intent.donate()
        case .select:
            let intent = OkIntent()
            intent.device = selectedDevice
            intent.donate()
        case .mute:
            let intent = MuteIntent()
            intent.device = selectedDevice
            intent.donate()
        case .volumeUp:
            let intent = VolumeUpIntent()
            intent.device = selectedDevice
            intent.donate()
        case .volumeDown:
            let intent = VolumeDownIntent()
            intent.device = selectedDevice
            intent.donate()
        case .playPause:
            let intent = PlayIntent()
            intent.device = selectedDevice
            intent.donate()
        default:
            return
        }
    }

    func donateAppLaunchIntent(_ link: AppLink) {
        let intent = LaunchAppIntent()
        intent.app = link
        intent.device = selectedDevice
        intent.donate()
    }

    func launchApp(_ app: AppLink) {
        donateAppLaunchIntent(app)
        incrementButtonPressCount(.inputAV1)
        Task {
            do {
                try await ecpSession?.launchApp(app.id)
            } catch {
                Log.connection.error("Error opening app \(app.id, privacy: .public): \(error, privacy: .public)")
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
#if DEBUG
        if Int.random(in: 1...20) == 1 {
            fatalError("Debug crash simulation")
        }
#endif
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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                requestReview()
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
    traits: .sampleData, .fixedLayout(width: 400, height: 800)
) {
    RemoteView()
        .environmentObject(RoamAppDelegate())
}
#endif
#endif
