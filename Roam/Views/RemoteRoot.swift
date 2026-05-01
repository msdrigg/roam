#if !os(macOS) && !os(watchOS)
import os
import SwiftUI
#if os(iOS)
import WatchConnectivity
#endif

/// Top-level container for iOS / visionOS. Owns the loaders and discovery
/// driving tasks, then renders one of three states:
///   • loading — devices haven't been fetched yet
///   • empty   — devices fetched but list is empty
///   • loaded  — TabView with one tab per device, plus settings in a sheet
struct RemoteRoot: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
#if os(iOS)
    @State private var showingAllDevices = false
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

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { appDelegate.navigationPath.selectedTab },
            set: { appDelegate.navigationPath.selectedTab = $0 }
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
#if os(iOS)
            .sheet(isPresented: $showingAllDevices) {
                DeviceSelectionSheet(
                    deviceIds: deviceIds,
                    selectedTab: Binding(
                        get: { appDelegate.navigationPath.selectedTab },
                        set: { appDelegate.navigationPath.selectedTab = $0 }
                    )
                )
            }
#endif
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
            .onChange(of: primaryDeviceLoader.device?.id, initial: true) { _, primaryId in
                guard let primaryId else { return }
                let target: AppTab = .device(primaryId)
                if appDelegate.navigationPath.selectedTab != target {
                    appDelegate.navigationPath.selectedTab = target
                }
            }
            .onChange(of: appDelegate.navigationPath.selectedTab) { _, newTab in
                guard case .device(let id) = newTab else { return }
                guard primaryDeviceLoader.device?.id != id else { return }
                Task {
                    do {
                        try await RoamDataHandler.shared.makePrimaryDevice(id: id)
                    } catch {
                        Log.userInteraction.error("Error setting primary device: \(error, privacy: .public)")
                    }
                }
            }
            .customAccentColorTint()
    }

    @ViewBuilder
    private var content: some View {
        if devicesLoader.devices == nil {
            loadingView
        } else if deviceIds.isEmpty {
            emptyView
        } else {
            tabView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "Loading devices…", comment: "Status while initial device list is being loaded"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 28) {
            Spacer()
            Label(
                String(localized: "Scanning for devices…", comment: "Empty-state heading shown when no devices have been discovered yet"),
                systemImage: "rays"
            )
            .symbolEffect(.variableColor)
            .font(.title2)
            .glowing()

            Button {
                appDelegate.navigationPath.showAddDevice = true
            } label: {
                Label(
                    String(localized: "Add a device manually", comment: "Button to manually add a device"),
                    systemImage: "plus"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassIfSupported(isProminent: true))
            .controlSize(.large)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabView: some View {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            phoneTabView
        } else if #available(iOS 18.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
#else
        if #available(iOS 18.0, visionOS 2.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
#endif
    }

    @available(iOS 18.0, visionOS 2.0, *)
    private var modernTabView: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(deviceIds, id: \.self) { deviceId in
                Tab(value: AppTab.device(deviceId)) {
                    DeviceTabContent(deviceId: deviceId, unreadMessages: unreadMessages)
                } label: {
                    DeviceTabLabel(deviceId: deviceId)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private var legacyTabView: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(deviceIds, id: \.self) { deviceId in
                DeviceTabContent(deviceId: deviceId, unreadMessages: unreadMessages)
                    .tabItem {
                        Label(
                            String(localized: "Device", comment: "Device tab fallback label"),
                            systemImage: "tv"
                        )
                    }
                    .tag(AppTab.device(deviceId))
            }
        }
    }

#if os(iOS)
    private var phoneTabView: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(deviceIds, id: \.self) { deviceId in
                DeviceTabContent(
                    deviceId: deviceId,
                    unreadMessages: unreadMessages,
                    showsDeviceActions: deviceIds.count > 1
                ) {
                    showingAllDevices = true
                }
                    .tag(AppTab.device(deviceId))
            }
        }
        .tabViewStyle(.page)
    }

    @MainActor
    private func transferDevicesToWatch(_ deviceIds: [String]) async {
        let devices = await RoamDataHandler.shared.requestAllDevices(deviceIds)
        WatchConnectivity.shared.transferDevices(WCSession.default, devices: devices)
    }
#endif
}

private struct DeviceTabContent: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    @State private var deviceLoader: DeviceLoader
    let deviceId: String
    let unreadMessages: Int
    let showsDeviceActions: Bool
    let showAllDevices: () -> Void

    init(
        deviceId: String,
        unreadMessages: Int,
        showsDeviceActions: Bool = false,
        showAllDevices: @escaping () -> Void = {}
    ) {
        self.deviceId = deviceId
        self.unreadMessages = unreadMessages
        self.showsDeviceActions = showsDeviceActions
        self.showAllDevices = showAllDevices
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    var body: some View {
        NavigationStack {
            RemoteViewContained(device: deviceLoader.device, unreadMessages: unreadMessages)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appDelegate.navigationPath.append(.settingsDestination(.global))
                        } label: {
                            Label(
                                String(localized: "Settings", comment: "Settings toolbar button label"),
                                systemImage: "gear"
                            )
                        }
                        .accessibilityIdentifier("SettingsButton")
                    }
#if os(iOS)
                    if showsDeviceActions {
                        ToolbarItem(placement: .bottomBar) {
                            Menu {
                                Button {
                                    showAllDevices()
                                } label: {
                                    Label(
                                        String(localized: "All devices", comment: "Menu item to show all configured devices"),
                                        systemImage: "tv"
                                    )
                                }

                                Button {
                                    appDelegate.navigationPath.showAddDevice = true
                                } label: {
                                    Label(
                                        String(localized: "Add a new device", comment: "Menu item to add another device"),
                                        systemImage: "plus"
                                    )
                                }
                            } label: {
                                Label(
                                    String(localized: "More", comment: "Toolbar button label for additional device actions"),
                                    systemImage: "ellipsis.circle"
                                )
                            }
                            .accessibilityIdentifier("MoreDevicesButton")
                        }
                    }
#endif
                }
        }
    }
}

private struct DeviceTabLabel: View {
    @State private var deviceLoader: DeviceLoader
    let deviceId: String

    init(deviceId: String) {
        self.deviceId = deviceId
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    var body: some View {
        Label(
            deviceLoader.device?.name ?? String(localized: "Loading…", comment: "Device tab label fallback before the device record loads"),
            systemImage: "tv"
        )
    }
}

#if os(iOS)
private struct DeviceSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let deviceIds: [String]
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            List(deviceIds, id: \.self) { deviceId in
                Button {
                    selectedTab = .device(deviceId)
                    dismiss()
                } label: {
                    DeviceSelectionRow(deviceId: deviceId, isSelected: selectedTab == .device(deviceId))
                }
            }
            .navigationTitle(String(localized: "All devices", comment: "Title for the sheet listing all configured devices"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "Button to dismiss a sheet")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DeviceSelectionRow: View {
    @State private var deviceLoader: DeviceLoader
    let deviceId: String
    let isSelected: Bool

    init(deviceId: String, isSelected: Bool) {
        self.deviceId = deviceId
        self.isSelected = isSelected
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    var body: some View {
        Label {
            Text(deviceLoader.device?.name ?? String(localized: "Loading…", comment: "Device list row fallback before the device record loads"))
        } icon: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "tv")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
    }
}
#endif
#endif
