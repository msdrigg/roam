#if !os(macOS) && !os(watchOS)
import os
import SwiftUI
#if os(iOS)
import WatchConnectivity
#endif

/// Minimum content size for the iPad split-view detail pane. Smaller windows
/// (Stage Manager / Slide Over) will scroll the remote rather than clip its
/// buttons.
private let iPadMinContentWidth: CGFloat = 460
private let iPadMinContentHeight: CGFloat = 560
/// Taller panes get the remote as a block this high, centered, instead of
/// its Spacers stretching the buttons across the whole pane.
private let iPadMaxContentHeight: CGFloat = 820

/// Top-level container for iOS / iPadOS / visionOS. Dispatches to:
///   • `PhoneHomeView` on iPhone (adaptive sidebar or grid and paged remote)
///   • `DeviceSplitRoot` on iPad and visionOS (sidebar + detail)
///
/// Owns the sheet plumbing and the scanning and watch-sync tasks.
struct RemoteRoot: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Environment(\.scenePhase) private var scenePhase

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    #if os(visionOS)
    @State private var visionOSKeyboardShown: Bool = CommandLine.arguments.contains("-OpenKeyboard")
    #endif
    #if os(iOS)
    @State private var iPadKeyboardShown: Bool = CommandLine.arguments.contains("-OpenKeyboard")
    #endif
    @State private var didApplyLaunchSettings: Bool = false

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanAutomatically: Bool = true

    private var deviceIds: [String] { devicesLoader.devices ?? [] }
    private var primaryDevice: Device? { primaryDeviceLoader.device }
    private var unreadMessages: Int { messageLoader.unreadCount }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Automatic scanning stops while backgrounded so a discovery-driven database
    /// write can't still be holding the app-group file lock when the process is
    /// suspended (0xdead10cc).
    private var discoveryPausedForBackground: Bool {
        discoveryPaused(for: scenePhase)
    }

    private var settingsNavigationPathBinding: Binding<[NavigationDestination]> {
        $appDelegate.navigationPath.settingsNavigationPath
    }

    private var editDeviceBinding: Binding<String?> {
        Binding(
            get: { appDelegate.navigationPath.showEditDevice },
            set: { appDelegate.navigationPath.showEditDevice = $0 }
        )
    }

    var body: some View {
        content
            .sheet(isPresented: $appDelegate.navigationPath.showAddDevice) {
                AddDeviceFlow()
            }
            .sheet(isPresented: $appDelegate.navigationPath.showSettings) {
                SettingsNavigationWrapper(path: settingsNavigationPathBinding) {
                    SettingsView(path: settingsNavigationPathBinding, destination: .global)
                }
            }
            .sheet(isPresented: Binding(
                get: { appDelegate.navigationPath.showEditDevice != nil },
                set: { newValue in
                    if !newValue {
                        appDelegate.navigationPath.showEditDevice = nil
                    }
                }
            )) {
                EditDeviceSheet(deviceIdToEdit: editDeviceBinding)
            }
            .task {
                guard !runningInPreview else { return }
                await RoamDataHandler.shared.initialize()
            }
            .task(id: "ssdp-\(scanAutomatically)-\(discoveryPausedForBackground)", priority: .background) {
                guard !runningInPreview, scanAutomatically else { return }
                guard !discoveryPausedForBackground else {
                    Log.scanning.notice("RemoteRoot skipping continual SSDP scan while backgrounded")
                    return
                }
                Log.scanning.notice("RemoteRoot starting continual SSDP scan")
                await appDelegate.discoveryCoordinator.ssdpActor.scanSSDPContinually()
                Log.scanning.notice("RemoteRoot continual SSDP scan returned")
            }
            .task(
                id: "ipv4-\(scanAutomatically)-\(primaryDevice == nil)-\(discoveryPausedForBackground)-\(String(describing: appDelegate.networkMonitor.networkConnection))"
            ) {
                guard !runningInPreview, scanAutomatically else { return }
                guard !discoveryPausedForBackground else {
                    Log.scanning.notice("RemoteRoot skipping IPV4 scan while backgrounded")
                    return
                }
                guard primaryDevice == nil else { return }
                Log.scanning.notice("RemoteRoot starting IPV4 scan")
                await appDelegate.discoveryCoordinator.ipv4Actor.scanIPV4Once()
                Log.scanning.notice("RemoteRoot IPV4 scan returned")
            }
            #if os(iOS)
            .task(id: deviceIds, priority: .background) {
                guard !runningInPreview, !deviceIds.isEmpty else { return }
                await transferDevicesToWatch(deviceIds)
                for await _ in AsyncTimerSequence.repeating(every: .seconds(60 * 10)) {
                    await transferDevicesToWatch(deviceIds)
                }
            }
            #endif
            .task { applyLaunchSettingsIfRequested() }
            .customAccentColorTint()
    }

    /// Honors `-OpenSettings` once the view tree is alive. Idempotent.
    /// `-OpenTipJar` implies it, since the tip jar is a SettingsView sheet.
    private func applyLaunchSettingsIfRequested() {
        guard !didApplyLaunchSettings else { return }
        didApplyLaunchSettings = true
        let args = CommandLine.arguments
        if args.contains("-OpenSettings") || args.contains("-OpenTipJar") {
            appDelegate.navigationPath.append(.settingsDestination(.global))
        }
    }

    @ViewBuilder
    private var content: some View {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            PhoneHomeView()
        } else {
            iPadRoot
        }
#else
        iPadRoot
#endif
    }

    private var iPadRoot: some View {
        DeviceSplitRoot { device in
            NavigationStack {
                #if os(visionOS)
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    RemoteViewContained(
                        device: device,
                        unreadMessages: unreadMessages,
                        externalShowKeyboard: $visionOSKeyboardShown,
                        hidesKeyboardToolbarButton: true
                    )
                    .frame(maxHeight: visionOSKeyboardShown ? .infinity : iPadMaxContentHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Same sizing as the iPad branch below: fill the
                    // viewport so the remote centers, keep the minimum so a
                    // small window scrolls, and match the viewport height
                    // exactly while the keyboard-entry overlay is up so its
                    // bottom-anchored text field clears the remote buttons.
                    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                        switch axis {
                        case .horizontal:
                            max(length, iPadMinContentWidth)
                        case .vertical:
                            visionOSKeyboardShown ? length : max(length, iPadMinContentHeight)
                        }
                    }
                }
                .scrollDisabled(visionOSKeyboardShown)
                // Only rubber-band on an axis when the remote actually
                // overflows the viewport. When it fits (the common case),
                // this kills the empty bounce in both directions.
                // .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
                .toolbar {
                    ToolbarItem(placement: .bottomOrnament) {
                        Button {
                            withAnimation { visionOSKeyboardShown.toggle() }
                        } label: {
                            Label(
                                String(localized: "Keyboard", comment: "visionOS bottom ornament button to toggle the keyboard"),
                                systemImage: "keyboard"
                            )
                        }
                        .accessibilityIdentifier("KeyboardButton")
                    }
                }
                #else
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    RemoteViewContained(
                        device: device,
                        unreadMessages: unreadMessages,
                        externalShowKeyboard: $iPadKeyboardShown
                    )
                    .frame(maxHeight: iPadKeyboardShown ? .infinity : iPadMaxContentHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A two-axis ScrollView proposes an unbounded size and
                    // pins its content top-leading, so `.frame(minWidth:)`
                    // alone leaves the remote in the top corner of a large
                    // pane. Sizing this container to the larger of the viewport
                    // and the minimum centers the height-capped remote above,
                    // while a smaller pane still scrolls. While the
                    // keyboard is up the height is the viewport exactly, so
                    // the keyboardEntry overlay (`.frame(maxHeight:
                    // .infinity, alignment: .bottom)`) anchors the text
                    // field just above the system keyboard.
                    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                        switch axis {
                        case .horizontal:
                            max(length, iPadMinContentWidth)
                        case .vertical:
                            iPadKeyboardShown ? length : max(length, iPadMinContentHeight)
                        }
                    }
                }
                // While the keyboard-entry text field is up, respect the
                // keyboard safe area so the field sits just above the system
                // keyboard. Otherwise iPadOS's automatic ScrollView keyboard
                // inset over-corrects and parks the field with a large gap
                // above the keyboard. While closed, ignore the keyboard so
                // an external keyboard's auto-correct bar doesn't shift
                // the remote layout.
                .scrollDisabled(iPadKeyboardShown)
                // Only rubber-band on an axis when the remote actually
                // overflows the viewport. When it fits (the common case),
                // this kills the empty bounce in both directions.
                // .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
                .ignoresSafeArea(.keyboard, edges: iPadKeyboardShown ? [] : .all)
                #endif
            }
        }
    }

#if os(iOS)
    @MainActor
    private func transferDevicesToWatch(_ deviceIds: [String]) async {
        let devices = await RoamDataHandler.shared.requestAllDevices(deviceIds)
        WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices)
    }
#endif
}
#endif
