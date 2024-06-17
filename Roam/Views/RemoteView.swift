import AppIntents
import AsyncAlgorithms
import AVFoundation
import Intents
import os
import StoreKit
import SwiftData
import SwiftUI
import Foundation
import TipKit

#if os(iOS) && !APPCLIP
import WatchConnectivity
#endif

let globalToolbarShrinkWidth: CGFloat = 300

let globalMajorActions: [RemoteButton] = [.power, .playPause, .mute, .headphonesMode]

private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name, order: .reverse)]
    )
    fd.relationshipKeyPathsForPrefetching = []
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]

    return fd
}()

private let messageFetchDescriptor: FetchDescriptor<Message> = {
    var fd = FetchDescriptor(
        predicate: #Predicate<Message> {
            !$0.viewed
        }
    )
    return fd
}()

enum KeyboardFocus {
    case entry
    case monitor
}

struct RemoteView: View {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )

    @Environment(\.scenePhase) var scenePhase
    #if !os(tvOS)
    @Environment(\.openWindow) var openWindow
    #endif
    @Environment(\.createDataHandler) var createDataHandler

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Query(deviceFetchDescriptor) private var devices: [Device]
    @Query(messageFetchDescriptor) private var unreadMessages: [Message]

    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    @State private var ecpSession: ECPSession?
    @StateObject private var networkMonitor = NetworkMonitor()
    @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

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

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true

    @Environment(\.verticalSizeClass) var verticalSizeClass

    @FocusState var focusKeyboardMonitor: KeyboardFocus?

    private var appLinkRows: Int {
        #if os(macOS) || os(tvOS)
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
        if manuallySelectedDevice != nil && manuallySelectedDevice?.deletedAt == nil {
            manuallySelectedDevice
        } else {
            devices.filter{
                $0.deletedAt == nil
            }.min { d1, d2 in
                (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
            }
        }
    }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State var isHorizontal: Bool = false
    @State var isSmallWidth: Bool = true

    @State var volume: Float = 0
    @State var lastVolumeChangeFromTv: Bool = false

    private struct IsHorizontalKey: PreferenceKey {
        static let defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    private struct IsSmallWidth: PreferenceKey {
        static let  defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    @Namespace var animation

    @Environment(\.uuidUpdater) private var updater

    var deviceStatusColor: Color {
        selectedDevice?.isOnline() ?? false ? Color.green : Color.secondary
    }

    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }

    func incrementButtonPressCount(_ key: RemoteButton) {
        buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
    }

    #if !os(tvOS) && !APPCLIP
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
    #endif

    var body: some View {
        if runningInPreview {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
                remotePage
            }
        } else {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
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
                            print("Setting focus early")
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
            .task {
                // Configure and load your tips at app launch.
                try? Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.groupContainer(identifier: "group.com.msdrigg.roam.tips"))
                ])
            }
            .task {
                while true {
                    if Task.isCancelled {
                        return
                    }

                    let createDataHandler = createDataHandler
                    Task.detached {
                        guard let ownedDataHandler = await createDataHandler() else {
                            return
                        }
                        await ownedDataHandler.refreshMessagesIfExpectingNewMessages()
                    }
                    try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000 * 3600)
                }
            }

            #if os(iOS) && !APPCLIP
            .task(id: devices.count, priority: .background) {
                    // Send devices to connected watch
                    WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices.map { $0.toAppEntity() })

                    for await _ in AsyncTimerSequence.repeating(every: .seconds(60 * 10)) {
                        WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices.map { $0.toAppEntity() })
                    }
                }
            #endif
                .onAppear {
                    networkMonitor.startMonitoring()
                }
                .onDisappear {
                    networkMonitor.stopMonitoring()
                }
                .task(priority: .background) {
                    await withDiscardingTaskGroup { taskGroup in
                        taskGroup.addTask {
                            await scanningActor.scanSSDPContinually()
                        }

                        if scanIpAutomatically {
                            taskGroup.addTask {
                                await scanningActor.scanIPV4Once()
                            }
                        }
                    }
                }
                .task(id: selectedDevice?.location, priority: .medium) {
                    Self.logger
                        .info("Creating ecp session with location \(String(describing: selectedDevice?.location))")
                    let oldECP = ecpSession
                    Task.detached {
                        await oldECP?.close()
                    }
                    ecpSession = nil
                    if let device = selectedDevice?.toAppEntity() {
                        do {
                            ecpSession = try ECPSession(device: device)
                            try await ecpSession?.configure()
                        } catch {
                            Self.logger.error("Error creating ECPSession: \(error)")
                        }
                    } else {
                        ecpSession = nil
                    }
                }
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    if let devId = selectedDevice?.persistentModelID {
                        await scanningActor.refreshSelectedDeviceContinually(id: devId)
                    }
                }
                .task(id: "\(headphonesModeEnabled),\(selectedDevice?.location ?? "--")") {
                    if !headphonesModeEnabled {
                        return
                    }
                    defer {
                        headphonesModeEnabled = false
                    }

                    if let device = selectedDevice, let ecpSession {
                        let location = device.location
                        let rtcpPort = device.rtcpPort
                        do {
                            let task = Task.detached {
                                try await listenContinually(
                                    ecpSession: ecpSession,
                                    location: location,
                                    rtcpPort: rtcpPort
                                )
                            }
                            defer {
                                if !task.isCancelled {
                                    task.cancel()
                                }
                            }
                            try await task.value
                            Self.logger.info("Listencontinually returned")
                        } catch {
                            Self.logger.warning("Catching error in pl handler \(error)")
                            // Increment errorTrigger if the error is anything but a cancellation error
                            if !(error is CancellationError) {
                                Self.logger.debug("Non-cancellation error in PL")
                                errorTrigger += 1
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
                        let isSmallWidth = proxy.size.width <= globalToolbarShrinkWidth

                        Color.clear.preference(key: IsHorizontalKey.self, value: isHorizontal)
                        Color.clear.preference(key: IsSmallWidth.self, value: isSmallWidth)
                    }
                )
                .onPreferenceChange(IsHorizontalKey.self) { value in
                    withAnimation {
                        isHorizontal = value
                    }
                }
                .onPreferenceChange(IsSmallWidth.self) { value in
                    withAnimation {
                        isSmallWidth = value
                    }
                }

            HStack {
                Spacer()
                VStack(alignment: .center, spacing: 10) {
                    #if os(tvOS)
                        HStack {
                            HStack {
                                Button(action: {
                                    keyboardLeaving = showKeyboardEntry
                                    withAnimation {
                                        showKeyboardEntry = !showKeyboardEntry
                                        if showKeyboardEntry {
                                            focusKeyboardMonitor = .entry
                                        } else {
                                            focusKeyboardMonitor = .monitor
                                        }
                                    }
                                }, label: {
                                    Label("Keyboard", systemImage: "keyboard")
                                })
                                .labelStyle(.iconOnly)
                                .disabled(selectedDevice == nil)
                                .font(.headline)
                                Spacer()
                            }
                            .focusSection()
                            HStack {
                                Spacer()
                                DevicePicker(
                                    devices: devices,
                                    device: Binding(get: {
                                        selectedDevice
                                    }, set: {
                                        manuallySelectedDevice = $0
                                    })
                                )
                                .font(.body)
                            }
                            .focusSection()
                        }
                    #endif

                    #if os(macOS)
                    HStack(alignment: .center) {
                        Spacer()
                            .layoutPriority(1)
                        DevicePicker(
                            devices: devices,
                            device: Binding(get: {
                                selectedDevice
                            }, set: {
                                manuallySelectedDevice = $0
                            })
                        )
                        .font(.body)
                        .frame(idealWidth: 100, maxWidth: 350)
                        .buttonStyle(.borderless)
                        .menuStyle(.button)
                        #if os(macOS)
                        .hoverHighlight()
                        #endif
                        Spacer()
                            .layoutPriority(1)
                    }
                    #elseif os(visionOS)
                    HStack(alignment: .center) {
                        Button(action: {
                            keyboardLeaving = showKeyboardEntry
                            withAnimation {
                                showKeyboardEntry = !showKeyboardEntry
                            }
                        }, label: {
                            Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
                        })
                        .focusable(true, interactions: [.activate, .edit])
                        .focused($focusKeyboardMonitor, equals: .monitor)
                        .onKeyPress { ke in
                            for shortcut in allKeyboardShortcuts {
                                if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                                    let title = shortcut.title
                                    Self.logger.info("Not handling key press because found shortcut with title \(title)")
                                    if let rb = title.matchingRemoteButton {
                                        pressButton(rb)
                                        return .handled
                                    }

                                    if title == .chatWithDeveloper{
                                        appDelegate.navigationPath.append(.messageDestination)
                                    } else if title == .keyboardShortcuts {
                                        appDelegate.navigationPath.append(.keyboardShortcutDestinaion)
                                    } else {
                                        Self.logger.warning("Unknown function for keyboard shortcut \(title)")
                                    }

                                    return .handled
                                }
                            }

                            pressKey(ke.key)
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
                            })
                        )
                        .font(.body)
                    }
                    #endif

                    if isHorizontal {
                        horizontalBody()
                            .disabled(selectedDevice == nil)
                    } else {
                        verticalBody()
                            .disabled(selectedDevice == nil)
                    }

#if !APPCLIP
                    if selectedDevice == nil {
                            #if os(macOS)
                                SettingsLink {
                                    Label(String(localized: "Setup a device to get started :)", comment: "Label on a button to open the device setup page"), systemImage: "gear")
                                        .padding(8)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .labelStyle(.titleAndIcon)

                            #else
                                NavigationLink(value: NavigationDestination.settingsDestination(.global)) {
                                    Label(String(localized: "Setup a device to get started :)", comment: "Label on a button to open the device setup page"), systemImage: "gear")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .labelStyle(.titleAndIcon)
                            #endif
                    }
#endif

                    if !hideUIForKeyboardEntry {
                        if unreadMessages.count > 0 {
                            // swiftlint:disable:next line_length
                            NotificationBanner(message: LocalizedStringResource("The developer chatted you back", comment: "Notification indicator that there was is message response waiting to be read"), onClick: {
#if os(macOS)
                                openWindow(id: "messages")
#else
                                appDelegate.navigationPath.append(NavigationDestination.messageDestination)
#endif
                            }, level: .info)
                        }
                        networkConnectivityBanner
                        Spacer().frame(maxHeight: 10)
                    }

                    if selectedDevice == nil {
                        NotificationBanner(message: LocalizedStringResource("Scanning for devices...", comment: "Notification indicator that devices are getting scanned for"), level: .info)
                            .frame(maxWidth: .infinity)
                    }

#if !os(macOS)
                    if showKeyboardEntry {
                        Spacer()
                            .frame(minHeight: 200)
                    }
#endif
                }
                Spacer()
            }
            #if !os(macOS)
            .overlay {
                #if os(iOS)
                    if controlVolumeWithHWButtons, !headphonesModeEnabled {
                        CustomVolumeSliderOverlay(volume: $volume) { volumeEvent in
                            let key: RemoteButton = switch volumeEvent.direction {
                            case .up:
                                .volumeUp
                            case .down:
                                .volumeDown
                            }
                            Self.logger
                                .info(
                                    "Pressing button \(String(describing: key)) with volume \(volume) after volume event \(String(describing: volumeEvent))"
                                )
                            pressButton(key)
                        }.id("VolumeOverlay")
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
                                        showKeyboardEntry = false
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
                                    str: $keyboardEntryText,
                                    showing: Binding<Bool>(get: {
                                        showKeyboardEntry
                                    }, set: { newVal in
                                        showKeyboardEntry = newVal
                                    }),
                                    onKeyPress: { char in
                                        pressKey(char)
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
            #if !os(tvOS) && !os(visionOS)
            .toolbar(id: "remote") {
                #if !os(macOS)
                    ToolbarItem(id: "keyboard", placement: .topBarLeading) {
                        Button(action: {
                            keyboardLeaving = showKeyboardEntry
                            withAnimation {
                                showKeyboardEntry = !showKeyboardEntry
                            }
                        }, label: {
                            Label(String(localized: "Keyboard", comment: "Label on a button to open the keyboard"), systemImage: "keyboard")
                        })
                        .focusable(true, interactions: [.activate, .edit])
                        .focused($focusKeyboardMonitor, equals: .monitor)
                        .onKeyPress { ke in
                            for shortcut in allKeyboardShortcuts {
                                if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                                    let title = shortcut.title
                                    Self.logger.info("Not handling key press because found shortcut with title \(title)")
                                    if let rb = title.matchingRemoteButton {
                                        pressButton(rb)
                                        return .handled
                                    }

                                    if title == .chatWithDeveloper{
                                        appDelegate.navigationPath.append(.messageDestination)
                                    } else if title == .keyboardShortcuts {
                                        appDelegate.navigationPath.append(.keyboardShortcutDestinaion)
                                    } else {
                                        Self.logger.warning("Unknown function for keyboard shortcut \(title)")
                                    }

                                    return .handled
                                }
                            }

                            pressKey(ke.key)
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
                            })
                        )
                        .font(.body)
                        .frame(idealWidth: 100, maxWidth: 350)
                    }
                #else
                ToolbarItem(id: "device-picker", placement: .navigation) {
                    if #available(macOS 15.0, *) {
                        EmptyView()
                    } else {
                        DevicePicker(
                            devices: devices,
                            device: Binding(get: {
                                selectedDevice
                            }, set: {
                                manuallySelectedDevice = $0
                            })
                        )
                        .font(.body)
                    }
                }
                #endif
            }
            #endif
                .onAppear {
                    scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer(), updater: {
                        updater?.update()
                    })
                }
            #if !os(visionOS)
                .sensoryFeedback(.error, trigger: errorTrigger)
            #endif
                .onChange(of: scenePhase) { _, newPhase in
                    inBackground = newPhase != ScenePhase.active
                }
            #if os(macOS)
                .onChange(of: appDelegate.messagingWindowOpenTrigger) { _, new in
                    if new != nil {
                        openWindow(id: "messages")
                    }
                }
            #endif
        }
        #if os(macOS)
        .onKeyDown({ key in pressKey(key.key) }, enabled: !showKeyboardEntry)
        #endif
        .font(.title2)
        .fontDesign(.rounded)
        #if !os(tvOS)
            .controlSize(.extraLarge)
        #endif
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .labelStyle(.iconOnly)
            .onOpenURL { incomingURL in
                Self.logger.info("App was opened via URL: \(incomingURL)")
                handleIncomingURL(incomingURL)
            }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.host == "roam.msd3.io" else {
            return
        }

        var path = url.pathComponents
        path.removeFirst()
        guard let dlpath = path.first, dlpath == "deep-link" || dlpath == "appclip" else {
            Self.logger.error("Getting Invalid URL path")
            return
        }
        let firstPath = path.first
        path.removeFirst()
        guard let action = path.first ?? firstPath else {
            Self.logger.warning("Getting url deep link with no action")
            return
        }
        Self.logger.info("Getting action \(action)")

        if action == "add-device" || action == "appclip" || action == "scan" {
            let queryParams = URLComponents(string: url.absoluteString)?.queryItems
            let name = queryParams?.first(where: { $0.name == "name" })?.value ?? "New device"
            // Get location param as location=IP or p=IPV4Hex
            guard let location = queryParams?.first(where: { $0.name == "location" })?.value ??
                queryParams?.first(where: { $0.name == "p" })?.value.flatMap({ hex in
                    let ipComponents = stride(from: 0, to: hex.count, by: 2).compactMap { index -> UInt8? in
                        let start = hex.index(hex.startIndex, offsetBy: index)
                        let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                        return UInt8(hex[start ..< end], radix: 16)
                    }
                    guard ipComponents.count == 4 else { return nil }
                    return ipComponents.map(String.init).joined(separator: ".")
                })
            else {
                Self.logger.error("Trying to add device with no location")
                return
            }

            let createDataHandler = createDataHandler
            Task.detached {
                let udn = queryParams?.first(where: { $0.name == "udn" })?.value ?? "roam:newdevice-\(UUID().uuidString)"
                await createDataHandler()?.addOrReplaceDevice(location: location, friendlyDeviceName: name, udn: udn)
            }
        }
        #if !APPCLIP
            if action == "feedback" {
                Self.logger.info("Attempting to open app debugging")
                appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.debugging))
            } else if action == "settings" {
                Self.logger.info("Attempting to open app settings")
                appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.global))
            } else if action == "about" {
                Self.logger.info("Attempting to open about page")
                appDelegate.navigationPath.append(NavigationDestination.aboutDestination)
            } else if action == "messages" {
                Self.logger.info("Attempting to open messages page")
                appDelegate.navigationPath.append(NavigationDestination.messageDestination)
            }
        #endif
    }

    @ViewBuilder
    var networkConnectivityBanner: some View {
        if networkMonitor.networkConnection == .none {
            NotificationBanner(message: LocalizedStringResource("No network connection", comment: "Warning indicator message that there is no network connection"))
        } else if networkMonitor.networkConnection == .remote || networkMonitor.networkConnection == .other {
            NotificationBanner(message: LocalizedStringResource("No WiFi connection detected", comment: "Warning indicator message that there is no WiFi network connection"), level: .warning)
        }
    }

    func horizontalBody() -> some View {
        VStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: globalButtonSpacing * 2) {
                if !hideUIForKeyboardEntry {
                    Spacer()
                    VStack {
                        Spacer().frame(maxHeight: 100)
                        // Center Controller with directional buttons
                        CenterController(pressCounter: buttonPressCount, action: pressButton)
                            .transition(.scale.combined(with: .opacity))
                            .matchedGeometryEffect(id: "centerController", in: animation)
                        Spacer().frame(maxHeight: 100)
                    }
                    #if os(macOS) || os(tvOS)
                    .focusSection()
                    #endif
                }
                Spacer()

                VStack(alignment: .center) {

                    // Row with Back and Home buttons
                    TopBar(pressCounter: buttonPressCount, action: pressButton)
                        .matchedGeometryEffect(id: "topBar", in: animation)
                    #if os(macOS) || os(tvOS)
                        .focusSection()
                    #endif

                    if !hideUIForKeyboardEntry {
                        Spacer().frame(maxHeight: 60)

                        // Grid of 9 buttons
                        ButtonGrid(
                            pressCounter: buttonPressCount,
                            action: pressButton,
                            enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                            disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                        )
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "buttonGrid", in: animation)
#if os(macOS) || os(tvOS)
.focusSection()
#endif
                    }
                }
                #if os(macOS) || os(tvOS)
                .focusSection()
                #endif
                Spacer()
            }
            #if os(macOS) || os(tvOS)
            .focusSection()
            #endif
            .frame(maxWidth: 600)

            if !showKeyboardEntry && selectedDevice != nil {
                Spacer()
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if os(macOS) || os(tvOS)
                    .focusSection()
                #endif
                #if !os(visionOS)
                .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif
            } else {
                Spacer()
            }
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
                #elseif !os(visionOS) && !os(tvOS)
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
                .layoutPriority(1)

            Spacer()
                    .frame(minHeight: 10)

            // Center Controller with directional buttons
            CenterController(pressCounter: buttonPressCount, action: pressButton)
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "centerController", in: animation)
                .layoutPriority(1)

            if !hideUIForKeyboardEntry {
                Spacer()
                    .frame(minHeight: 10)
                // Grid of 9 buttons
                ButtonGrid(
                    pressCounter: buttonPressCount,
                    action: pressButton,
                    enabled: headphonesModeEnabled ? Set([.headphonesMode]) : Set([]),
                    disabled: headphonesModeDisabled ? Set([.headphonesMode]) : Set([])
                )
                .transition(.scale.combined(with: .opacity))
                .matchedGeometryEffect(id: "buttonGrid", in: animation)
                .layoutPriority(1)
            }

            if !showKeyboardEntry && selectedDevice != nil {
                Spacer()
                    .frame(minHeight: 10)
                AppLinksView(deviceId: selectedDevice?.udn, rows: appLinkRows, handleOpenApp: launchApp)
                    .matchedGeometryEffect(id: "appLinksBar", in: animation)
                #if !os(visionOS)
                    .sensoryFeedback(SensoryFeedback.impact, trigger: buttonPressCount(.inputAV1))
                #endif
                    .layoutPriority(1)

                Spacer()
            } else {
                Spacer()
            }
        }
    }

    func launchApp(_ app: AppLinkAppEntity) {
        #if !os(tvOS) && !APPCLIP
            donateAppLaunchIntent(app)
        #endif
        incrementButtonPressCount(.inputAV1)
        Task.detached {
            do {
                try await ecpSession?.openApp(app)
            } catch {
                Self.logger.error("Error opening app \(app.id): \(error)")
            }
        }
        Task.detached {
            await createDataHandler()?.setSelectedApp(app.modelId)
        }
    }

    func pressButton(_ button: RemoteButton) {
        incrementButtonPressCount(button)
        if globalMajorActions.contains(button) {
            handleMajorUserAction()
        }
        #if !os(tvOS) && !APPCLIP
            donateButtonIntent(button)
        #endif
        if button == .headphonesMode {
            headphonesModeEnabled.toggle()
            return
        }

        Task {
            do {
                try await ecpSession?.pressButton(button)
            } catch {
                Self.logger.info("Error sending button to device via ecp: \(error)")
            }
        }
    }

    func pressKey(_ key: KeyEquivalent) {
        Self.logger.trace("Getting keyboard press \(key.character)")
        if let button = RemoteButton.fromCharacter(character: key.character) {
            incrementButtonPressCount(button)
            if globalMajorActions.contains(button) {
                handleMajorUserAction()
            }
            #if !os(tvOS) && !APPCLIP
                donateButtonIntent(button)
            #endif
        }

        if let ecpSession {
            Self.logger.info("Getting ecp session to send data to")
            Task {
                do {
                    try await ecpSession.pressCharacter(key.character)
                } catch {
                    Self.logger.error("Error pressing character \(key.character) on device \(error)")
                }
            }
            return
        }
    }
}

#if DEBUG
#Preview("Remote horizontal") {
    RemoteView()
        .modelContainer(previewContainer)
}
#endif
