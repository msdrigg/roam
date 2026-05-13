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

/// Top-level container for iOS / iPadOS / visionOS. Dispatches to:
///   • `PhoneHomeView` on compact iPhone (weather-card grid → paged remote)
///   • `DeviceSplitRoot` on iPad and visionOS (sidebar + detail)
///
/// Owns the long-lived sheet plumbing (Add device, Settings, Edit device) and
/// the background scanning + watch-sync tasks, so the inner roots stay focused
/// on layout.
struct RemoteRoot: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    #if os(visionOS)
    @State private var visionOSKeyboardShown: Bool = false
    #endif

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanAutomatically: Bool = true

    private var deviceIds: [String] { devicesLoader.devices ?? [] }
    private var primaryDevice: Device? { primaryDeviceLoader.device }
    private var unreadMessages: Int { messageLoader.unreadCount }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
            .task(id: "ssdp-\(scanAutomatically)", priority: .background) {
                guard !runningInPreview, scanAutomatically else { return }
                Log.scanning.notice("RemoteRoot starting continual SSDP scan")
                await appDelegate.discoveryCoordinator.ssdpActor.scanSSDPContinually()
                Log.scanning.notice("RemoteRoot continual SSDP scan returned")
            }
            .task(
                id: "ipv4-\(scanAutomatically)-\(primaryDevice == nil)-\(String(describing: appDelegate.networkMonitor.networkConnection))"
            ) {
                guard !runningInPreview, scanAutomatically else { return }
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
            .customAccentColorTint()
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
                    .frame(minWidth: iPadMinContentWidth, minHeight: iPadMinContentHeight)
                }
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
                    RemoteViewContained(device: device, unreadMessages: unreadMessages)
                        .frame(minWidth: iPadMinContentWidth, minHeight: iPadMinContentHeight)
                }
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
