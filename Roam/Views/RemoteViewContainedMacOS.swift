#if os(macOS)
    import AppIntents
    import Foundation
    import Intents
    import os
    import StoreKit
    import SwiftUI

    let globalToolbarShrinkWidth: CGFloat = 300

    let globalMajorActions: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

    enum KeyboardFocus {
        case monitor
    }

    struct RemoteViewContained: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openSettings) private var openSettings
        @Environment(\.openWindow) private var openWindow

        @EnvironmentObject private var appDelegate: RoamAppDelegate

        @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
        @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
        @State private var messageLoader = MessageListLoader(dataHandler: .shared)
        @State private var scanningActor: DeviceDiscoveryActor?
        @State private var ssdpActor: DeviceDiscoveryActor?
        @State private var buttonPresses: [RemoteButton: Int] = [:]
        @State private var headphonesModeEnabled = false
        @State private var errorTrigger = 0
        @State private var columnVisibility: NavigationSplitViewVisibility = .all

        @FocusState private var focusKeyboardMonitor: KeyboardFocus?

        @AppStorage(UserDefaultKeys.localNetworkPermissionGranted) private
            var networkPermissionGranted = false
        @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private
            var shouldScanIPRangeAutomatically = true
        @Namespace private var animation

        private let isInMenuBar: Bool

        init(isInMenuBar: Bool = false) {
            self.isInMenuBar = isInMenuBar
        }

        private var appLinkRows: Int {
            2
        }

        private var deviceIds: [String] {
            devicesLoader.devices ?? []
        }

        private var isLoadingDevices: Bool {
            if devicesLoader.isLoading || primaryDeviceLoader.isLoading
                || devicesLoader.devices == nil
            {
                return true
            }

            guard let devices = devicesLoader.devices, !devices.isEmpty else {
                return false
            }

            guard let selectedDevice else {
                return true
            }

            return !devices.contains(selectedDevice.id)
        }

        private var ecpSession: ECPWebsocketClient? {
            appDelegate.ecpMonitor.ecpClient
        }

        private var ecpSessionState: ECPMonitor {
            appDelegate.ecpMonitor
        }

        private var headphonesModeDisabled: Bool {
            !(selectedDevice?.supportsDatagram ?? true)
        }

        private var networkMonitor: NetworkMonitor {
            appDelegate.networkMonitor
        }

        private var runningInPreview: Bool {
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        }

        private var scanSSDP: Bool {
            shouldScanIPRangeAutomatically
        }

        private var selectedDevice: Device? {
            primaryDeviceLoader.device
        }

        private var unreadMessages: Int {
            messageLoader.unreadCount
        }

        private var minimumContentWidth: CGFloat? {
            isInMenuBar ? nil : 560
        }

        private var minimumContentHeight: CGFloat? {
            isInMenuBar ? nil : 560
        }

        var body: some View {
            configuredContent
        }

        @ViewBuilder
        private var content: some View {
            if isLoadingDevices {
                loadingDevicesView
            } else if deviceIds.isEmpty {
                noDevicesView
            } else if isInMenuBar {
                menuBarRemoteView
                    .buttonStyle(.bordered)
            } else if deviceIds.count == 1 {
                singleDeviceRemoteView
            } else {
                splitRemoteView
            }
        }

        private var configuredContent: some View {
            content
                .buttonStyle(.glassIfSupported)
                .task {
                    guard !runningInPreview else { return }

                    focusKeyboardMonitor = .monitor
                    while !Task.isCancelled {
                        try? await Task.sleep(duration: 1)

                        if focusKeyboardMonitor == nil {
                            focusKeyboardMonitor = .monitor
                        }
                    }
                }
                .defaultFocus($focusKeyboardMonitor, .monitor, priority: .userInitiated)
                .onChange(of: focusKeyboardMonitor) {
                    if focusKeyboardMonitor == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            focusKeyboardMonitor = .monitor
                        }
                    }
                }
                .task {
                    await RoamDataHandler.shared.initialize()
                }
                .task(id: deviceIds) {
                    await ensureSelectedDevice()
                }
                .task {
                    do {
                        Log.network.notice(
                            "\("Checking", privacy: .public) for local network permission")
                        let permission = try await requestLocalNetworkAuthorization()
                        Log.network.notice(
                            "Got permission check result \(permission, privacy: .public)")
                        networkPermissionGranted = permission
                    } catch {
                        Log.network.error(
                            "Error requesting local network authorization \(error, privacy: .public)"
                        )
                    }
                }
                .onAppear {
                    Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
                    Log.scanning.notice(
                        "RemoteViewContained creating discovery actors scanSSDP=\(scanSSDP, privacy: .public) selectedDeviceId=\(selectedDevice?.id ?? "nil", privacy: .public)"
                    )
                    scanningActor = DeviceDiscoveryActor()
                    ssdpActor = DeviceDiscoveryActor()
                }
                .onDisappear {
                    Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
                }
                .task(id: "\(ssdpActor != nil && scanSSDP)", priority: .background) {
                    let actorReady = ssdpActor != nil
                    Log.scanning.notice(
                        "RemoteViewContained SSDP task fired actorReady=\(actorReady, privacy: .public) scanSSDP=\(scanSSDP, privacy: .public) selectedDeviceId=\(selectedDevice?.id ?? "nil", privacy: .public)"
                    )
                    guard scanSSDP else {
                        Log.scanning.notice(
                            "RemoteViewContained SSDP task skipping because scanSSDP is false")
                        return
                    }
                    guard let ssdpActor else {
                        Log.scanning.warning(
                            "RemoteViewContained SSDP task skipping because ssdpActor is nil")
                        return
                    }

                    Log.scanning.notice("RemoteViewContained starting continual SSDP scan")
                    await ssdpActor.scanSSDPContinually()
                    Log.scanning.notice("RemoteViewContained continual SSDP scan returned")
                }
                .task(
                    id:
                        "\(scanningActor != nil && selectedDevice == nil && scanSSDP)-\(networkMonitor.networkConnection)"
                ) {
                    let actorReady = scanningActor != nil
                    Log.scanning.notice(
                        "RemoteViewContained IPV4 task fired actorReady=\(actorReady, privacy: .public) scanSSDP=\(scanSSDP, privacy: .public) selectedDeviceId=\(selectedDevice?.id ?? "nil", privacy: .public) networkConnection=\(String(describing: networkMonitor.networkConnection), privacy: .public)"
                    )
                    guard scanSSDP else {
                        Log.scanning.notice(
                            "RemoteViewContained IPV4 task skipping because scanSSDP is false")
                        return
                    }
                    guard selectedDevice == nil else {
                        Log.scanning.notice(
                            "RemoteViewContained IPV4 task skipping because selectedDevice is not nil"
                        )
                        return
                    }
                    guard let scanningActor else {
                        Log.scanning.warning(
                            "RemoteViewContained IPV4 task skipping because scanningActor is nil")
                        return
                    }

                    Log.scanning.notice("RemoteViewContained starting IPV4 scan")
                    await scanningActor.scanIPV4Once()
                    Log.scanning.notice("RemoteViewContained IPV4 scan returned")
                }
                .task(id: selectedDevice?.id, priority: .medium) {
                    for await _ in exponentialBackoff(min: 30, max: 3600) {
                        if let selectedDevice, let ecpSession {
                            Log.connection
                                .info(
                                    "Refreshing device \(selectedDevice.location, privacy: .public) after backoff"
                                )
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
                .task(id: selectedDevice?.location, priority: .medium) {
                    Log.connection
                        .notice(
                            "Creating ecp session with location \(String(describing: selectedDevice?.location), privacy: .public)"
                        )
                    ecpSessionState.setDevice(selectedDevice)
                }
                .task(id: "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")") {
                    guard headphonesModeEnabled else {
                        return
                    }
                    defer {
                        headphonesModeEnabled = false
                    }

                    if let device = selectedDevice, let ecpSession {
                        do {
                            try await listenContinually(
                                ecpSession: ecpSession,
                                location: device.location,
                                rtcpPort: device.rtcpPort
                            )
                            Log.headphones.notice(
                                "Listencontinually returned \(#fileID, privacy: .public)"
                            )
                        } catch {
                            Log.headphones.warning(
                                "Catching error in pl handler \(error, privacy: .public)")
                            if !(error is CancellationError) {
                                Log.headphones.notice(
                                    "Non-cancellation error in PL \(#fileID, privacy: .public)")
                                errorTrigger += 1
                            }
                        }
                    }
                }
                .onKeyDown({ key in pressKey(key.key, modifiers: key.modifiers) }, enabled: true)
                .onWindowFocused {
                    Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")
                    appDelegate.navigationPath.focusedWindow = .remote
                }
                .sensoryFeedback(.error, trigger: errorTrigger)
                .sheet(isPresented: appDelegate.navigationPath.showingAddDevice(for: .remote)) {
                    AddDeviceFlow()
                }
                .frame(minWidth: minimumContentWidth, minHeight: minimumContentHeight)
        }

        private var loadingDevicesView: some View {
            VStack(spacing: 14) {
                Spacer()

                Image(systemName: "rays")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor)

                Text("Loading devices")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Spacer()

                NetworkConnectivityBanner()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }

        private var noDevicesView: some View {
            VStack(spacing: 18) {
                Spacer()

                Label("Scanning for devices", systemImage: "rays")
                    .labelStyle(.titleAndIcon)
                    .font(.title3)
                    .symbolEffect(.variableColor)
                    .padding()
                    .glowing()

                Button("Add a device manually", systemImage: "plus") {
                    appDelegate.navigationPath.showAddDevice = true
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .customKeyboardShortcut(.addDevice)

                Spacer()

                NetworkConnectivityBanner()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var menuBarRemoteView: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    MacDeviceToolbarMenu(
                        deviceIds: deviceIds,
                        selectedDevice: selectedDevice,
                        selection: deviceSelection
                    )
                    .menuStyle(.button)

                    Spacer(minLength: 12)

                    settingsToolbarButtons
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .buttonStyle(.accessoryBar)

                remoteDetail
            }
        }

        private var singleDeviceRemoteView: some View {
            NavigationStack {
                remoteDetail
            }
            .toolbar {
                settingsNavigationToolbarContent
            }
        }

        private var splitRemoteView: some View {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: deviceSelection) {
                    Section("Devices") {
                        ForEach(deviceIds, id: \.self) { deviceId in
                            MacDeviceSidebarItem(id: deviceId)
                                .tag(deviceId)
                        }
                        .onMove(perform: moveDevices)
                    }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                remoteDetail
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    MacDeviceToolbarMenu(
                        deviceIds: deviceIds,
                        selectedDevice: selectedDevice,
                        selection: deviceSelection
                    )
                }

                settingsNavigationToolbarContent
            }
            .tint(.none)
        }

        @ToolbarContentBuilder
        private var settingsNavigationToolbarContent: some ToolbarContent {
            ToolbarItem(id: "settings-flexible-space") {
                Spacer()
            }

            ToolbarItem(id: "settings") {
                settingsToolbarButtons
                    .buttonStyle(.accessoryBar)
            }
        }

        @ViewBuilder
        private var settingsToolbarButtons: some View {
            if isInMenuBar {
                Button {
                    openWindow(id: "main")
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApp.forceFront("main")
                    }
                } label: {
                    Label("Open main window", systemImage: "macwindow.on.rectangle")
                }
                .labelStyle(.iconOnly)
            } else {
                Button {
                    openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApp.forceFront("com_apple_SwiftUI_Settings_window")
                    }
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("SettingsButton")
            }
        }

        private var remoteDetail: some View {
            ZStack {
                Color.clear

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    remoteControls
                        .customAccentColorForeground()
                        .tint(.none)
                        .disabled(selectedDevice == nil)
                        .font(.title2)
                        .fontDesign(.rounded)
                        .controlSize(.small)
                        .labelStyle(.iconOnly)

                    if unreadMessages > 0 && !inScreenshotTestingContext() {
                        NotificationBanner(
                            message: String(
                                localized: "The developer chatted you back",
                                comment:
                                    "Notification indicator that there was is message response waiting to be read"
                            ),
                            onClick: {
                                openWindow(id: "messages")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    NSApp.forceFront("messages")
                                }
                            },
                            level: .info
                        )
                        .padding(.top, 12)
                    }

                    NetworkConnectivityBanner()
                        .padding(.top, unreadMessages > 0 ? 6 : 12)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }

        private var remoteControls: some View {
            VStack(alignment: .center, spacing: 30) {
                VStack(alignment: .center, spacing: 30) {
                    TopBar(
                        pressCounter: buttonPressCount,
                        action: pressButton,
                        usesNativeGlassButtons: isInMenuBar
                    )
                    .matchedGeometryEffect(id: "topBar", in: animation)
                    .focusSection()

                    CenterController(
                        pressCounter: buttonPressCount,
                        action: pressButton,
                        usesNativeGlassButtons: isInMenuBar
                    )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "centerController", in: animation)
                    .focusSection()

                    ButtonGrid(
                        pressCounter: buttonPressCount,
                        action: pressButton,
                        enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                        disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([]),
                        usesNativeGlassButtons: isInMenuBar
                    )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: "buttonGrid", in: animation)
                    .focusSection()
                }
                .fixedSize()

                if selectedDevice != nil {
                    AppLinksView(
                        deviceId: selectedDevice?.udn,
                        rows: appLinkRows,
                        handleOpenApp: launchApp,
                    )
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }

        private var deviceSelection: Binding<String?> {
            Binding<String?> {
                selectedDevice?.id
            } set: { deviceId in
                guard let deviceId else { return }
                Task {
                    do {
                        try await RoamDataHandler.shared.makePrimaryDevice(id: deviceId)
                    } catch {
                        Log.userInteraction.error(
                            "Error setting selected device \(error, privacy: .public)")
                    }
                }
            }
        }

        private func ensureSelectedDevice() async {
            guard let firstDeviceId = deviceIds.first else { return }
            guard selectedDevice == nil || !deviceIds.contains(selectedDevice?.id ?? "") else {
                return
            }

            do {
                try await RoamDataHandler.shared.makePrimaryDevice(id: firstDeviceId)
            } catch {
                Log.userInteraction.error(
                    "Error setting initial selected device \(error, privacy: .public)")
            }
        }

        private func moveDevices(fromOffsets: IndexSet, toOffset: Int) {
            Task {
                do {
                    try await RoamDataHandler.shared.reorderDevices(
                        fromOffsets: fromOffsets, toOffset: toOffset)
                } catch {
                    Log.userInteraction.error("Error reordering devices \(error, privacy: .public)")
                }
            }
        }

        private func buttonPressCount(_ key: RemoteButton) -> Int {
            buttonPresses[key] ?? 0
        }

        private func donateAppLaunchIntent(_ link: AppLink) {
            let intent = LaunchAppIntent()
            intent.app = link
            intent.device = selectedDevice
            intent.donate()
        }

        private func donateButtonIntent(_ key: RemoteButton) {
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

        private func handleMajorUserAction() {
            var count = UserDefaults.standard.integer(forKey: UserDefaultKeys.userMajorActionCount)
            count += 1
            UserDefaults.standard.set(count, forKey: UserDefaultKeys.userMajorActionCount)

            if shouldRequestReview() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SKStoreReviewController.requestReview()
                }

                UserDefaults.standard.set(
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
                    forKey: UserDefaultKeys.appVersionAtLastReviewRequest
                )
                UserDefaults.standard.set(Date(), forKey: UserDefaultKeys.dateOfLastReviewRequest)
            }
        }

        private func incrementButtonPressCount(_ key: RemoteButton) {
            buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
        }

        private func launchApp(_ app: AppLink) {
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

        private func pressButton(_ button: RemoteButton) {
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
                    Log.connection.notice(
                        "Error sending button to device via ecp: \(error, privacy: .public)")
                }
            }
            #if DEBUG
                if Int.random(in: 1...20) == 1 {
                    fatalError("Debug crash simulation")
                }
            #endif
        }

        private func pressKey(_ key: KeyEquivalent, modifiers: EventModifiers) {
            Task {
                await pressKeyAsync(key, modifiers: modifiers)
            }
        }

        private func pressKeyAsync(_ key: KeyEquivalent, modifiers: EventModifiers) async {
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
                    Log.connection
                        .error(
                            "Error pressing character \(key.character, privacy: .public) on device \(error, privacy: .public)"
                        )
                }
            }
        }

        private func shouldRequestReview() -> Bool {
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
    }

    private struct MacDeviceSidebarItem: View {
        @State private var deviceLoader: DeviceLoader

        private let id: String

        init(id: String) {
            self.id = id
            self._deviceLoader = State(
                initialValue: DeviceLoader(deviceId: id, dataHandler: .shared))
        }

        var body: some View {
            Label {
                Text(deviceLoader.device?.name ?? "Loading...")
                    .lineLimit(1)
            } icon: {
                Image(systemName: (deviceLoader.device?.isOnline() ?? false) ? "tv.fill" : "tv")
                    .foregroundStyle(
                        (deviceLoader.device?.isOnline() ?? false)
                            ? Color.accentColor : Color.secondary)
            }
        }
    }

    private struct MacDeviceToolbarMenu: View {
        let deviceIds: [String]
        let selectedDevice: Device?
        let selection: Binding<String?>

        var body: some View {
            Menu {
                ForEach(deviceIds, id: \.self) { deviceId in
                    MacDeviceToolbarMenuItem(id: deviceId, selectedDeviceId: selectedDevice?.id) {
                        selection.wrappedValue = deviceId
                    }
                }
            } label: {
                Text(selectedDevice?.name ?? "Device")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .leading)
            }
        }
    }

    private struct MacDeviceToolbarMenuItem: View {
        @State private var deviceLoader: DeviceLoader

        let id: String
        let selectedDeviceId: String?
        let action: () -> Void

        init(id: String, selectedDeviceId: String?, action: @escaping () -> Void) {
            self.id = id
            self.selectedDeviceId = selectedDeviceId
            self.action = action
            _deviceLoader = State(initialValue: DeviceLoader(deviceId: id, dataHandler: .shared))
        }

        var body: some View {
            Button(action: action) {
                Label(
                    deviceLoader.device?.name ?? "Loading...",
                    systemImage: selectedDeviceId == id ? "checkmark" : "tv")
            }
        }
    }

    #if DEBUG
        #Preview(
            "Remote macOS",
            traits: .sampleData, .fixedLayout(width: 780, height: 620)
        ) {
            RemoteView()
                .environmentObject(RoamAppDelegate())
        }
    #endif
#endif
