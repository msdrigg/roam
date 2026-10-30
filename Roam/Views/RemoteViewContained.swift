#if !os(macOS)
    import AppIntents
    import AVFoundation
    import Intents
    import os
    import StoreKit
    import SwiftUI
    import TipKit
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
        // Used by `decoratedRemotePage` to re-probe local-network permission on
        // foreground, which visionOS needs too - so it lives outside the
        // iOS-only block below.
        @Environment(\.scenePhase) private var scenePhase
        #if os(iOS)
            @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor:
                Color = Color("AccentColor")
            @State private var showPastedUrlOffer: Bool = false
            // Outlives `showKeyboardEntry` while the keyboard slides away, so
            // the field rides down with it instead of leaving first.
            @State private var entryMounted: Bool = false
            // Once an offer is accepted or dismissed, don't re-offer until the
            // pasteboard contents actually change. `changeCount` is metadata,
            // so reading it never triggers the system paste notice.
            @State private var lastHandledPasteboardChangeCount: Int = -1
            @AppStorage(UserDefaultKeys.disablePastedUrlSuggestions) private
                var disablePastedUrlSuggestions: Bool = false
            private let pastedUrlOfferTip = PastedUrlOfferTip()
        #endif
        @State private var bottomBannerVisible: Bool = false
        @State private var errorTrigger: Int = 0
        @AppStorage(UserDefaultKeys.localNetworkPermissionGranted) private
            var networkPermissionGranted: Bool = false
        @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

        private let device: Device?
        private let unreadMessages: Int
        private let isInMenuBar: Bool
        private let externalShowKeyboard: Binding<Bool>?
        private let hidesKeyboardToolbarButton: Bool
        private let isActive: Bool
        private let preloads: Bool

        // Whether the app row loads its icons. Set once and kept, so paging
        // back to a page doesn't load them again.
        @State private var iconsLoaded: Bool

        private var ecpSessionState: ECPMonitor {
            appDelegate.ecpMonitor
        }

        private var ecpSession: ECPWebsocketClient? {
            appDelegate.ecpMonitor.ecpClient
        }

        private var headphonesMode: HeadphonesModeController {
            appDelegate.headphonesMode
        }

        private var headphonesModeEnabled: Bool {
            headphonesMode.isEnabled(for: selectedDevice?.id)
        }

        // Only the active page presents the error, so neighbor pages in the
        // pager don't stack duplicate alerts.
        private var headphonesError: Binding<Error?> {
            Binding(
                get: { isActive ? headphonesMode.error : nil },
                set: { headphonesMode.error = $0 }
            )
        }

        private var timedMutePhase: TimedMutePhase {
            appDelegate.timedMute.phase(forDevice: selectedDevice?.id)
        }

        private var showKeyboardEntry: Bool {
            return showKeyboardEntryManual
        }

        init(
            device: Device? = nil,
            unreadMessages: Int = 0,
            isInMenuBar: Bool = false,
            externalShowKeyboard: Binding<Bool>? = nil,
            hidesKeyboardToolbarButton: Bool = false,
            isActive: Bool = true,
            preloads: Bool = false
        ) {
            self.device = device
            self.unreadMessages = unreadMessages
            self.isInMenuBar = isInMenuBar
            self.externalShowKeyboard = externalShowKeyboard
            self.hidesKeyboardToolbarButton = hidesKeyboardToolbarButton
            self.isActive = isActive
            self.preloads = preloads
            self._iconsLoaded = State(initialValue: isActive)
        }

        var headphonesModeDisabled: Bool {
            !(selectedDevice?.supportsDatagram ?? true)
        }

        /// True when the device tells us it isn't a TV, i.e. a stick or Express
        /// with no speakers of its own. Volume still gets sent - it leaves over
        /// HDMI-CEC - this only drives a one-time hint about enabling CEC.
        var volumeRoutedOverHDMI: Bool {
            selectedDevice?.isTV == false
        }

        var hideAppsForKeyboardEntry: Bool {
            #if os(visionOS)
                return showKeyboardEntry
            #else
                return false
            #endif
        }

        @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private
            var controlVolumeWithHWButtons: Bool = true

        @Environment(\.horizontalSizeClass) var horizontalSizeClass
        @Environment(\.verticalSizeClass) var verticalSizeClass

        @FocusState var focusKeyboardMonitor: KeyboardFocus?

        private var appLinkRows: Int {
            if verticalSizeClass == .compact {
                return 1
            }
            #if os(iOS)
                // iPhone Duo's outer display (644pt for the remote) and its
                // inner display held sideways are too short for a second row
                // once a banner shows. iPhone 16e gets 711pt.
                if UIDevice.current.userInterfaceIdiom == .phone, remoteHeight > 0, remoteHeight < 660 {
                    return 1
                }
            #endif
            return 2
        }

        #if os(iOS)
            @State var windowScene: UIWindowScene?

            // The negative bottom padding intentionally pulls content below the
            // safe area when nothing renders at the bottom edge. Switch to a
            // positive value while a banner or the pasted-URL offer is showing
            // so that content stays above the pager's floating button bar
            // instead of clipping below it - the flexible Spacers above
            // compress to absorb the difference.
            private var iOSBottomPadding: CGFloat {
                if showPastedUrlOffer || bottomBannerVisible {
                    return 10
                }
                if UIDevice.current.userInterfaceIdiom == .phone {
                    return isHorizontal ? -16 : -32
                }
                return 10
            }
        #endif

        private var selectedDevice: Device? {
            device
        }

        private var isDeviceOnline: Bool {
            DeviceLivenessMonitor.shared.isOnline(selectedDevice)
        }

        private var runningInPreview: Bool {
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        }

        @State var controlledIsHorizontal: Bool?
        @State private var remoteHeight: CGFloat = 0
        @AppStorage(UserDefaultKeys.macosKeysWindowHorizontal) private var windowWasLastHorizontal:
            Bool = false

        var isHorizontal: Bool {
            if let controlledIsHorizontal {
                return controlledIsHorizontal
            }
            #if os(visionOS)
                return windowWasLastHorizontal
            #else
                return UIDevice.current.orientation.isLandscape
            #endif
        }

        @State var volume: Float = 0
        @State var lastVolumeChangeFromTv: Bool = false

        @ScaledMetric var buttonRadius = globalButtonRadius

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
                Log.network.error(
                    "Error requesting local network authorization \(error, privacy: .public)")
            }
        }

        private func handleAppear() {
            Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
            headphonesMode.remoteAppeared()
        }

        private func handleDisappear() {
            Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
            headphonesMode.remoteDisappeared()
        }

        private func refreshDeviceBackoffTask() async {
            // Only the active page may refresh: inactive pager pages share the
            // same ECP session, which points at the *active* device - refreshing
            // through it would write another device's info into this record.
            // The refresh writes to the shared database, so it waits for the
            // foreground (see `discoveryPaused`).
            guard isActive, !discoveryPaused(for: scenePhase) else { return }
            for await _ in exponentialBackoff(min: 30, max: 3600) {
                if Task.isCancelled {
                    return
                }
                guard let selectedDevice else {
                    Log.connection
                        .info("No selected device to refresh")
                    return
                }
                guard let ecpSession,
                    ecpSession.location.absoluteString == selectedDevice.location
                else {
                    Log.connection
                        .info("Skipping refresh because shared ECP session is not for this device")
                    continue
                }
                Log.connection
                    .info(
                        "Refreshing device \(selectedDevice.location, privacy: .public) after backoff"
                    )
                let handler = RoamDataHandler.shared
                await handler.refreshDevice(
                    client: ECPWebsocketRefreshClient(
                        id: selectedDevice.id,
                        client: ecpSession,
                        location: selectedDevice.location
                    )
                )
            }
        }

        private func ecpSessionLocationTask() async {
            // Only the active page owns the shared ECP session. In the phone
            // pager, neighbor pages appear during a swipe - without this guard
            // they steal the session mid-swipe, and if the swipe bounces back
            // the visible page (which never disappeared) never re-claims it,
            // leaving the session pointed at the wrong device.
            guard isActive else { return }
            Log.connection.notice(
                "Creating ecp session with location \(String(describing: selectedDevice?.location), privacy: .public)"
            )
            if let device = selectedDevice {
                headphonesMode.deviceSelected(device.id)
                self.ecpSessionState.setDevice(device)
            } else {
                self.ecpSessionState.setDevice(nil)
            }
        }

        // Neighbor pages load their icons after a pause, so a swipe that
        // lands keeps the main thread for the page coming into view.
        private func loadIconsTask() async {
            guard !iconsLoaded else { return }
            if isActive {
                iconsLoaded = true
            } else if preloads {
                try? await Task.sleep(for: .milliseconds(800))
                if !Task.isCancelled {
                    iconsLoaded = true
                }
            }
        }

        private func syncExternalKeyboardOnAppear() {
            if let externalShowKeyboard,
                externalShowKeyboard.wrappedValue != showKeyboardEntryManual
            {
                showKeyboardEntryManual = externalShowKeyboard.wrappedValue
            }
        }

        private func propagateKeyboardManualChange(_ new: Bool) {
            if let externalShowKeyboard,
                externalShowKeyboard.wrappedValue != new
            {
                externalShowKeyboard.wrappedValue = new
            }
        }

        private func propagateExternalKeyboardChange(_ new: Bool?) {
            guard let new, showKeyboardEntryManual != new else { return }
            if new {
                // `keyboardLeaving` is the edge-triggered signal that tells
                // `KeyboardEntry` to resign focus synchronously inside
                // `dismissKeyboardEntry`, before the parent's view-removal
                // animation commits. If it's still `true` from the previous
                // close, the next `dismissKeyboardEntry` is a no-op edge and
                // the iOS keyboard lingers until the view tears down. Reset
                // it here on the external-binding open path; the toolbar
                // path (`toggleKeyboardEntry`) already does this implicitly
                // via `keyboardLeaving = showKeyboardEntry`.
                keyboardLeaving = false
            }
            withAnimation {
                showKeyboardEntryManual = new
            }
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
                // Re-probe whenever the app returns to the foreground so the
                // permission banner clears (or appears) without a relaunch.
                .task(id: scenePhase) {
                    guard scenePhase != .background else { return }
                    await networkPermissionTask()
                }
                .onAppear(perform: handleAppear)
                .onDisappear(perform: handleDisappear)
                // Both ids include `isActive` so a page (re)claims the shared
                // session and resumes refreshing the moment it becomes the
                // active pager page - not just when it appears.
                .task(
                    id: "\(isActive),\(discoveryPaused(for: scenePhase)),\(selectedDevice?.id ?? "--")",
                    priority: .medium
                ) {
                    await refreshDeviceBackoffTask()
                }
                .task(id: "\(isActive),\(selectedDevice?.location ?? "--")", priority: .medium) {
                    await ecpSessionLocationTask()
                }
                .task(id: "\(isActive),\(preloads)", priority: .background) { await loadIconsTask() }
                #if os(iOS)
                    // Re-check whenever the page becomes the active pager page,
                    // the app foregrounds, or the device changes.
                    .task(id: pasteboardCheckTaskId) { await checkForPastedUrl() }
                    .task(id: showKeyboardEntry) { await handleEntryVisibilityChange(showKeyboardEntry) }
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
                        Log.headphones.notice(
                            "Not handling key press because found shortcut with title \(title, privacy: .public)"
                        )
                        if let rb = title.matchingRemoteButton {
                            pressButton(rb)
                            return .handled
                        }
                        if title == .chatWithDeveloper {
                            appDelegate.navigationPath.openMessages()
                        } else if title == .keyboardShortcuts {
                            appDelegate.navigationPath.openKeyboardShortcuts()
                        } else {
                            Log.userInteraction.warning(
                                "Unknown function for keyboard shortcut \(title, privacy: .public)")
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
                        Button(
                            action: toggleKeyboardEntry,
                            label: {
                                Label(
                                    String(
                                        localized: "Keyboard",
                                        comment: "Label on a button to open the keyboard"),
                                    systemImage: "keyboard")
                            }
                        )
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

        #if !os(visionOS)
            private var toolbarKeyboardButton: some View {
                Button(
                    action: toggleKeyboardEntry,
                    label: {
                        Label(
                            String(
                                localized: "Keyboard",
                                comment: "Label on a button to open the keyboard"),
                            systemImage: "keyboard")
                    }
                )
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
                guard let id = ecpSessionState.textEditStatus.texteditId,
                    UIPasteboard.general.hasStrings
                else {
                    Log.userInteraction.notice(
                        "Not pasting due to empty textedit id (\(ecpSessionState.textEditStatus.texteditId ?? "none", privacy: .public)) or false UI pasteboard hasStrings (\(UIPasteboard.general.hasStrings), privacy: .public)"
                    )
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
                            Log.userInteraction.error(
                                "Error cutting text: \(error, privacy: .public)")
                        }
                    }
                }
            }

            private func handleToolbarKeyPress(_ ke: KeyPress) -> KeyPress.Result {
                for shortcut in allKeyboardShortcuts {
                    if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                        let title = shortcut.title
                        Log.userInteraction.notice(
                            "Not handling key press because found shortcut with title \(title, privacy: .public)"
                        )
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
                            Log.userInteraction.warning(
                                "Unknown function for keyboard shortcut \(title, privacy: .public)")
                        }
                        return .handled
                    }
                }
                pressKey(ke.key, modifiers: ke.modifiers)
                return .handled
            }
        #endif

        #if os(iOS)
            private func handleVolumeEvent(_ volumeEvent: VolumeEvent) {
                let key: RemoteButton =
                    switch volumeEvent.direction {
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
                // Gate on `isActive` so off-screen pager pages don't also install
                // hardware volume button interceptors - only the visible page should
                // be live.
                if controlVolumeWithHWButtons && !headphonesModeEnabled && isActive {
                    CustomVolumeSliderOverlay(volume: $volume, changeVolume: handleVolumeEvent)
                        .id("VolumeOverlay")
                        .frame(maxWidth: 1)
                }
            }

            // MARK: - Pasted URL detection

            private var pasteboardCheckTaskId: String {
                "\(scenePhase == .active),\(isActive),\(disablePastedUrlSuggestions),\(selectedDevice?.location ?? "--")"
            }

            // Pattern detection only says *whether* the pasteboard looks like a
            // web URL - it never reads the value, so the system "pasted from"
            // notice is not triggered. The actual contents are only read when
            // the user taps the system PasteButton in the offer banner (a
            // sanctioned paste affordance, which is also notice-free), and the
            // URL is parsed/validated there before anything is sent.
            private func checkForPastedUrl() async {
                // Only the focused remote page should offer the suggestion - not
                // off-screen pager pages, and never outside this view (e.g. the
                // phone home screen, which doesn't contain this view at all).
                guard isActive, scenePhase == .active, selectedDevice != nil else {
                    return
                }
                guard !disablePastedUrlSuggestions,
                    UIPasteboard.general.changeCount != lastHandledPasteboardChangeCount
                else {
                    withAnimation { showPastedUrlOffer = false }
                    return
                }
                do {
                    let patterns = try await UIPasteboard.general.detectedPatterns(
                        for: [\.probableWebURL])
                    if !Task.isCancelled {
                        withAnimation {
                            showPastedUrlOffer = patterns.contains(\.probableWebURL)
                        }
                    }
                } catch {
                    // Thrown when the pasteboard is empty or detection fails -
                    // either way there's nothing to offer.
                    if !Task.isCancelled {
                        withAnimation { showPastedUrlOffer = false }
                    }
                }
            }

            private var pastedUrlOfferMessage: String {
                String(
                    localized: "Open copied video",
                    comment:
                        "Banner offering to open a copied streaming link (e.g. YouTube) on the selected device"
                )
            }

            private func handlePastedUrlOffer(_ items: [String]) {
                lastHandledPasteboardChangeCount = UIPasteboard.general.changeCount
                withAnimation { showPastedUrlOffer = false }
                guard let first = items.first, let (appId, params) = parsePastedUrl(first)
                else {
                    Log.userInteraction.notice(
                        "Pasted url offer accepted but url did not parse to a launchable app")
                    errorTrigger += 1
                    return
                }
                incrementButtonPressCount(.inputAV1)
                Task {
                    do {
                        try await ecpSession?.launchApp(appId, params: params)
                    } catch {
                        Log.connection.error(
                            "Error opening pasted url app=\(appId, privacy: .public) params=\(params, privacy: .public): \(error, privacy: .public)"
                        )
                    }
                }
            }

            private func dismissPastedUrlOffer() {
                lastHandledPasteboardChangeCount = UIPasteboard.general.changeCount
                withAnimation { showPastedUrlOffer = false }
            }

            @ViewBuilder
            private var pastedUrlBanner: some View {
                if showPastedUrlOffer {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(customAccentColor)
                        Text(pastedUrlOfferMessage)
                            .truncationMode(.tail)

                        PasteButton(payloadType: String.self, onPaste: handlePastedUrlOffer)
                            .buttonBorderShape(.capsule)
                            .controlSize(.mini)
                            .labelStyle(.iconOnly)

                        BannerDismissButton(action: dismissPastedUrlOffer)
                    }
                    .bannerPill(tint: customAccentColor)
                    .popoverTip(pastedUrlOfferTip)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

        private var keyboardEntryField: some View {
            KeyboardEntry(
                showing: keyboardEntryShowingBinding,
                onKeyPress: handleKeyboardEntryPress,
                leaving: keyboardLeaving
            )
            .frame(maxWidth: isHorizontal ? 480 : .infinity)
        }

        #if os(iOS)
            @ViewBuilder
            private var keyboardScrim: some View {
                if showKeyboardEntry {
                    Button(action: dismissKeyboardEntry) {
                        Color.black.opacity(0.55).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }

            private func handleEntryVisibilityChange(_ showing: Bool) async {
                if showing {
                    entryMounted = true
                    return
                }
                guard entryMounted else { return }
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled {
                    entryMounted = false
                }
            }

            @ViewBuilder
            private var keyboardEntryFloating: some View {
                if entryMounted {
                    KeyboardFollowingContainer(
                        content: keyboardEntryField
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    )
                    .transition(.opacity)
                }
            }
        #else
            @ViewBuilder
            private var keyboardEntryOverlay: some View {
                if showKeyboardEntry {
                    VStack(spacing: 0) {
                        Spacer()
                        keyboardEntryField
                            .padding(.bottom, 10)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        #endif

        @ViewBuilder
        private var mobileOverlays: some View {
            #if os(iOS)
                volumeOverlay
            #else
                keyboardEntryOverlay
            #endif
        }

        private func handleRemoteSizeChange(_ size: CGSize) {
            remoteHeight = size.height
            let horizontal = size.width > size.height
            guard horizontal != controlledIsHorizontal else { return }
            withAnimation {
                Log.userInteraction.notice(
                    "Remote layout horizontal changed to \(horizontal, privacy: .public)")
                controlledIsHorizontal = horizontal
                windowWasLastHorizontal = horizontal
            }
        }

        #if os(iOS)
            @ViewBuilder
            private var iOSDeviceNameHeader: some View {
                if selectedDevice?.name != nil {
                    if isHorizontal {
                        Spacer()
                    }

                    deviceTitleHeader
                        .frame(maxWidth: .infinity)
                    // In portrait, the trailing Spacer separates the device name
                    // from the body's TopBar. In landscape there's no headroom for
                    // it - keeping it competes with `horizontalBody`'s internal
                    // Spacers and pushes the title above the visible area.
                    if !isHorizontal {
                        Spacer()
                    }
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
            #if os(iOS)
                iOSDeviceNameHeader
            #elseif os(visionOS)
                visionOSKeyboardHeader
            #endif
        }

        private func openMessages() {
            appDelegate.navigationPath.openMessages()
        }

        @ViewBuilder
        private var banners: some View {
            TimedMuteStatusPill(
                phase: timedMutePhase,
                onUnmute: appDelegate.timedMute.unmuteNow,
                onDismiss: appDelegate.timedMute.dismissMessage
            )
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.3), value: timedMutePhase)
            #if os(iOS)
                pastedUrlBanner
            #endif
            // Suppress the unread-developer-message banner under
            // screenshot tests - it's data-driven by an untrusted
            // count from the testing data fixture and clutters
            // marketing captures.
            if unreadMessages > 0 && !inScreenshotTestingContext() {
                NotificationBanner(
                    message: String(
                        localized: "The developer chatted you back",
                        comment:
                            "Notification indicator that there was is message response waiting to be read"
                    ), onClick: openMessages, level: .info, systemImage: "bubble.left.fill")
                .padding(.bottom, 8)
            }
            NetworkConnectivityBanner()
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
            // On iOS, compact vertical (landscape iPhone) doesn't have the
            // headroom for `.extraLarge` bordered buttons - the natural
            // HStack height pushes the device-name header off the top of the
            // screen. Step down to `.large` so the layout fits without
            // clipping. Other platforms keep `.extraLarge` unconditionally.
            #if os(iOS)
                .controlSize(verticalSizeClass == .compact ? .large : .extraLarge)
            #else
                .controlSize(.extraLarge)
            #endif
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .labelStyle(.iconOnly)
        }

        private var mainColumn: some View {
            VStack(alignment: .center, spacing: 0) {
                topHeader
                directionalBody
                banners
                #if !os(iOS)
                    if showKeyboardEntry {
                        Spacer()
                    }
                #endif
            }
            .onPreferenceChange(BottomBannerVisibleKey.self) { visible in
                withAnimation(.spring(duration: 0.3)) {
                    bottomBannerVisible = visible
                }
            }
        }

        var remotePage: some View {
            // The orientation is read from the space the page is offered, not
            // from the ZStack below: a ZStack grows to its tallest child, so on
            // a screen too short for the vertical layout it would report that
            // overflow as a portrait size and keep the vertical layout.
            GeometryReader { proxy in
                remoteStack
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .onChange(of: proxy.size, initial: true) { _, size in
                        handleRemoteSizeChange(size)
                    }
            }
            #if os(iOS)
                // The keyboard never resizes the remote. Only the entry
                // follows it, from the keyboard's frame notifications.
                .ignoresSafeArea(.keyboard)
                .overlay {
                    keyboardScrim
                        .ignoresSafeArea()
                }
                .overlay { keyboardEntryFloating }
            #endif
            .customAccentColorTint()
            .defaultFocus($focusKeyboardMonitor, .monitor, priority: .userInitiated)
        }

        private var remoteStack: some View {
            ZStack {
                HStack(alignment: .top) {
                    Spacer()
                    mainColumn
                        .frame(maxHeight: .infinity)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                .overlay { mobileOverlays }
                .padding(.horizontal, 20)
                #if os(visionOS)
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
                #if os(iOS)
                    .padding(.bottom, iOSBottomPadding)
                #else
                    .padding(.bottom, 10)
                #endif
                #if !os(visionOS)
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
                    .sensoryFeedback(.error, trigger: headphonesMode.errorCount) { _, _ in isActive }
                #endif
                .alertingError(message: "Headphones mode error", error: headphonesError)
            }
        }

        func horizontalBody() -> some View {
            VStack(alignment: .center) {
                HStack(alignment: .center, spacing: globalButtonSpacing * 2) {
                    Spacer()
                    VStack {
                        Spacer().frame(maxHeight: 100)
                        // Center Controller with directional buttons
                        CenterController(pressCounter: buttonPressCount, action: pressButton)
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "centerController", in: animation)
                        Spacer().frame(maxHeight: 100)
                    }
                    Spacer()

                    VStack(alignment: .center) {

                        // Row with Back and Home buttons
                        TopBar(pressCounter: buttonPressCount, action: pressButton)
                            .matchedGeometryEffect(id: "topBar", in: animation)

                        Spacer().frame(maxHeight: 60)

                        // Grid of 9 buttons
                        ButtonGrid(
                            pressCounter: buttonPressCount,
                            action: pressButton,
                            enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                            disabled: Set([]),
                            volumeRoutedOverHDMI: volumeRoutedOverHDMI,
                            headphonesModeUnsupported: headphonesModeDisabled,
                            onTimedMute: startTimedMute
                        )
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "buttonGrid", in: animation)
                        .zIndex(1)
                    }
                    Spacer()
                }
                .frame(maxWidth: 600)

                if !hideAppsForKeyboardEntry && selectedDevice != nil {
                    Spacer()
                    AppLinksView(
                        deviceId: selectedDevice?.udn, rows: appLinkRows, showsIcons: iconsLoaded,
                        handleOpenApp: launchApp
                    )
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                    .allowsHitTesting(isActive)
                    #if !os(visionOS)
                        .sensoryFeedback(
                            SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                    #endif
                } else {
                    Spacer()
                }
            }
            // Landscape iPhone otherwise crowds the buttons + app row against
            // each other; visually shrink the whole horizontal layout 10%.
            .scaleEffect(0.9)
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

                    ButtonGrid(
                        pressCounter: buttonPressCount,
                        action: pressButton,
                        enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                        disabled: Set([]),
                        volumeRoutedOverHDMI: volumeRoutedOverHDMI,
                        headphonesModeUnsupported: headphonesModeDisabled
                    )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "buttonGrid", in: animation)
                    .focusSection()

                    if !hideAppsForKeyboardEntry && selectedDevice != nil {
                        AppLinksView(
                            deviceId: selectedDevice?.udn, rows: appLinkRows, showsIcons: iconsLoaded,
                            handleOpenApp: launchApp
                        )
                        .matchedGeometryEffect(id: "appLinksBar", in: animation)
                        .allowsHitTesting(isActive)
                        .sensoryFeedback(
                            SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                    }
                }
                .fixedSize()
            #else
                VStack(alignment: .center, spacing: 0) {
                    Spacer()
                        .frame(maxHeight: 30)

                    // Row with Back and Home buttons
                    TopBar(pressCounter: buttonPressCount, action: pressButton)
                        .matchedGeometryEffect(id: "topBar", in: animation)

                    Spacer()

                    // Center Controller with directional buttons
                    CenterController(pressCounter: buttonPressCount, action: pressButton)
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "centerController", in: animation)

                    Spacer()
                    // Grid of 9 buttons
                    ButtonGrid(
                        pressCounter: buttonPressCount,
                        action: pressButton,
                        enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                        disabled: Set([]),
                        volumeRoutedOverHDMI: volumeRoutedOverHDMI,
                        headphonesModeUnsupported: headphonesModeDisabled,
                        onTimedMute: startTimedMute
                    )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "buttonGrid", in: animation)
                    .zIndex(1)

                    if !hideAppsForKeyboardEntry && selectedDevice != nil {
                        Spacer()
                        AppLinksView(
                            deviceId: selectedDevice?.udn, rows: appLinkRows, showsIcons: iconsLoaded,
                            handleOpenApp: launchApp
                        )
                        .matchedGeometryEffect(id: "appLinksBar", in: animation)
                        .allowsHitTesting(isActive)
                        #if !os(visionOS)
                            .sensoryFeedback(
                                SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                        #endif
                    } else {
                        Spacer()
                    }
                    Spacer()
                }
            #endif
        }

        func shouldRequestReview() -> Bool {
            let userActionCount = UserDefaults.standard.integer(
                forKey: UserDefaultKeys.userMajorActionCount)
            let lastVersionAsked = UserDefaults.standard.string(
                forKey: UserDefaultKeys.appVersionAtLastReviewRequest)
            let lastDateAsked =
                UserDefaults.standard.object(forKey: UserDefaultKeys.dateOfLastReviewRequest)
                as? Date

            guard
                let currentVersion = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            else {
                return false
            }

            if userActionCount < 10 {
                return false
            }

            if currentVersion == lastVersionAsked {
                return false
            }

            if let lastDate = lastDateAsked,
                Calendar.current.date(byAdding: .month, value: 1, to: lastDate)! > Date()
            {
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
                    Log.connection.error(
                        "Error opening app \(app.id, privacy: .public): \(error, privacy: .public)")
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
                headphonesMode.toggle(device: selectedDevice, ecpSession: ecpSession)
                return
            }
            if button == .mute {
                // A manual toggle means the user has taken mute back over.
                if timedMutePhase.isInFlight {
                    appDelegate.timedMute.cancel()
                } else {
                    appDelegate.timedMute.dismissMessage()
                }
            }

            Task {
                do {
                    try await ecpSession?.pressButton(button)
                } catch {
                    Log.connection.notice(
                        "Error sending button to device via ecp: \(error, privacy: .public)")
                }
            }
            #if DEBUG
                // Deliberate crash-recovery exercise - never during UI/
                // screenshot capture, where a random fatalError corrupts the
                // run (the app launches dozens of times per locale sweep).
                if Int.random(in: 1...100) == 1, !inUITestingContext() {
                    fatalError("Debug crash simulation")
                }
            #endif
        }

        func startTimedMute(_ seconds: Int) {
            guard let selectedDevice else { return }
            incrementButtonPressCount(.mute)
            handleMajorUserAction()
            appDelegate.timedMute.start(TimedMuteTarget(device: selectedDevice), duration: TimeInterval(seconds))
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
                    try await ecpSession.pressCharacter(
                        getModifiedCharacter(key, modifiers: modifiers))
                } catch {
                    Log.connection.error(
                        "Error pressing character \(key.character, privacy: .public) on device \(error, privacy: .public)"
                    )
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
