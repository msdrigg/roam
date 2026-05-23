#if !os(watchOS)
import SwiftUI

/// Shared `NavigationSplitView` host used on iPad, macOS, and visionOS.
///
/// The sidebar shows a card-styled list of devices with swipe / context-menu
/// actions to edit and delete, a pull-down rescan, an "+ Add device" footer,
/// and a Settings toolbar button. Selection drives the primary device — the
/// detail pane is provided by the caller so each platform can pass its native
/// `RemoteViewContained` variant.
struct DeviceSplitRoot<Detail: View>: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    #if os(macOS)
    @Environment(\.openSettings) private var openMacSettings
    #endif
    @Environment(\.layoutDirection) private var systemLayoutDirection

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
        // SwiftUI's NavigationSplitView collapses the sidebar into a
        // dimming popover in RTL on iPad / visionOS even when
        // `columnVisibility == .all` and the window is wide enough for the
        // inline layout. Pin the split itself to LTR so the columns stay
        // side-by-side, then restore the system layout direction inside
        // each pane so Arabic text and per-view layouts mirror normally.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .environment(\.layoutDirection, systemLayoutDirection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .navigationTitle(String(
                    localized: "Devices",
                    comment: "Title of the device sidebar in the split-view layout"
                ))
                #if !os(macOS)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
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
            // Keep the detail pane LTR too. The remote view's inner
            // ScrollView centers its content horizontally; under RTL the
            // ScrollView anchors content to the trailing (right) edge and
            // clips the left half of the remote. The only RTL-sensitive
            // bits inside the detail pane are SwiftUI `Text` views, which
            // mirror per-character via bidi regardless of the surrounding
            // layoutDirection.
            detail(selectedDevice)
        }
        #if !os(macOS)
        .environment(\.layoutDirection, .leftToRight)
        #endif
        #if os(visionOS)
        // visionOS's default split-view style collapses the sidebar into a
        // floating ornament/popover in RTL even with .all visibility. The
        // .balanced style keeps both columns inline at fixed widths so the
        // detail pane actually renders within the window.
        .navigationSplitViewStyle(.balanced)
        #endif
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
                    localized: "Scanning for devices",
                    comment: "Sidebar empty-state heading while no devices have been discovered"
                ),
                systemImage: "rays"
            )
            .labelStyle(.titleAndIcon)
            .font(.title3)
            .symbolEffect(.variableColor)
            .multilineTextAlignment(.center)
            .padding()
            .glowing()

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
