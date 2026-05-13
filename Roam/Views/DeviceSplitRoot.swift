#if !os(watchOS)
import SwiftUI

/// Shared `NavigationSplitView` host used on iPad, macOS, and visionOS.
///
/// The sidebar shows a card-styled list of devices with swipe / context-menu
/// actions to edit and delete, a pull-down rescan, an "+ Add device" footer,
/// and a `...` toolbar menu (Add device manually / Settings). Selection drives
/// the primary device — the detail pane is provided by the caller so each
/// platform can pass its native `RemoteViewContained` variant.
struct DeviceSplitRoot<Detail: View>: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    #if os(macOS)
    @Environment(\.openSettings) private var openMacSettings
    #endif

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var scanIPV4Actor: DeviceDiscoveryActor?
    @State private var scanSSDPActor: DeviceDiscoveryActor?

    private let detail: (Device?) -> Detail

    init(@ViewBuilder detail: @escaping (Device?) -> Detail) {
        self.detail = detail
    }

    private var deviceIds: [String] { devicesLoader.devices ?? [] }
    private var selectedDevice: Device? { primaryDeviceLoader.device }
    private var isEmpty: Bool { devicesLoader.devices != nil && deviceIds.isEmpty }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .navigationTitle(String(
                    localized: "Devices",
                    comment: "Title of the device sidebar in the split-view layout"
                ))
                #if !os(macOS)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        #if !os(visionOS)
                        Button {
                            appDelegate.navigationPath.showAddDevice = true
                        } label: {
                            Label(
                                String(
                                    localized: "Add device",
                                    comment: "Toolbar button on iPad sidebar to add a new device"
                                ),
                                systemImage: "plus"
                            )
                        }
                        .accessibilityIdentifier("AddDeviceButton")
                        #endif

                        Button {
                            openSettings()
                        } label: {
                            Label(
                                String(
                                    localized: "Settings",
                                    comment: "Toolbar button on iPad/visionOS sidebar to open Settings"
                                ),
                                systemImage: "gear"
                            )
                        }
                        .accessibilityIdentifier("SettingsButton")
                    }
                }
                #endif
        } detail: {
            detail(selectedDevice)
        }
        .onAppear {
            if scanIPV4Actor == nil { scanIPV4Actor = DeviceDiscoveryActor() }
            if scanSSDPActor == nil { scanSSDPActor = DeviceDiscoveryActor() }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if isEmpty {
            emptySidebar
        } else {
            deviceList
        }
    }

    private var deviceList: some View {
        List(selection: deviceSelection) {
            ForEach(deviceIds, id: \.self) { deviceId in
                DeviceSidebarCard(deviceId: deviceId)
                    .tag(deviceId)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .deviceActions(
                        deviceId: deviceId,
                        deviceName: nil,
                        onEdit: { appDelegate.navigationPath.showEditDevice = deviceId }
                    )
            }
            .onMove(perform: moveDevices)
        }
        .refreshable {
            await runManualScan()
        }
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 12)
        }
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addDeviceFooter
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 18) {
            Spacer()
            Label(
                String(
                    localized: "Scanning for devices…",
                    comment: "Sidebar empty-state heading while no devices have been discovered"
                ),
                systemImage: "rays"
            )
            .symbolEffect(.variableColor)
            .font(.headline)
            .multilineTextAlignment(.center)

            Button {
                appDelegate.navigationPath.showAddDevice = true
            } label: {
                Label(
                    String(
                        localized: "Add a device manually",
                        comment: "Button shown in the empty sidebar to manually add a device"
                    ),
                    systemImage: "plus"
                )
                .labelStyle(.titleAndIcon)
            }
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var addDeviceFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                appDelegate.navigationPath.showAddDevice = true
            } label: {
                Label(
                    String(
                        localized: "Add device",
                        comment: "Footer button under the sidebar device list to add a new device"
                    ),
                    systemImage: "plus.circle"
                )
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Toolbar

    private func openSettings() {
        #if os(macOS)
        openMacSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.forceFront("com_apple_SwiftUI_Settings_window")
        }
        #else
        appDelegate.navigationPath.append(.settingsDestination(.global))
        #endif
    }

    // MARK: - Selection / scanning

    private var deviceSelection: Binding<String?> {
        Binding<String?> {
            selectedDevice?.id
        } set: { newId in
            guard let newId else { return }
            Task {
                do {
                    try await RoamDataHandler.shared.makePrimaryDevice(id: newId)
                } catch {
                    Log.userInteraction.error(
                        "Error setting selected device \(error, privacy: .public)")
                }
            }
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

    private func runManualScan() async {
        guard let scanIPV4Actor, let scanSSDPActor else { return }
        await performManualDeviceScan(ipv4Actor: scanIPV4Actor, ssdpActor: scanSSDPActor)
    }
}
#endif
