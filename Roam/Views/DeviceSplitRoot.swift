#if !os(watchOS)
import SwiftUI

/// Shared `NavigationSplitView` host used on iPad, macOS, and visionOS.
///
/// The sidebar shows a card-styled list of devices with swipe / context-menu
/// actions to edit and delete, a pull-down rescan, an "+ Add device" footer,
/// and a Settings toolbar button. Selection drives the primary device - the
/// detail pane is provided by the caller so each platform can pass its native
/// `RemoteViewContained` variant.
struct DeviceSplitRoot<Detail: View>: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    #if os(macOS)
    @Environment(\.openSettings) private var openMacSettings
    #endif
    @Environment(\.layoutDirection) private var systemLayoutDirection
    @Environment(\.scenePhase) private var scenePhase

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var scanIPV4Actor: DeviceDiscoveryActor?
    @State private var scanSSDPActor: DeviceDiscoveryActor?
    #if os(macOS)
    @State private var window: NSWindow?
    #endif

    private let detail: (Device?) -> Detail
    private let minimumDetailWidth: CGFloat?

    init(
        minimumDetailWidth: CGFloat? = nil,
        @ViewBuilder detail: @escaping (Device?) -> Detail
    ) {
        self.minimumDetailWidth = minimumDetailWidth
        self.detail = detail
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: UserDefaultKeys.deviceSidebarHidden) {
            _columnVisibility = State(initialValue: .detailOnly)
        }
        #endif
    }

    /// The window has to be narrowable to the detail column alone once the
    /// sidebar is hidden. Only the scene root's frame sets the window's
    /// minimum, so this travels up as `MinimumWindowWidthKey`. Raising a
    /// minimum never grows the window, so a window left narrow is widened by
    /// hand when the sidebar returns.
    private var minimumSplitWidth: CGFloat? {
        guard let minimumDetailWidth else { return nil }
        if columnVisibility == .detailOnly {
            return minimumDetailWidth
        }
        return minimumDetailWidth + sidebarMinimumWidth
    }

    private let sidebarMinimumWidth: CGFloat = 240

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
                .navigationSplitViewColumnWidth(min: sidebarMinimumWidth, ideal: 280, max: 340)
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
            #if os(macOS)
            detail(selectedDevice)
                .navigationSplitViewColumnWidth(
                    min: minimumDetailWidth ?? 0, ideal: minimumDetailWidth ?? 0)
            #else
            detail(selectedDevice)
            #endif
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
        #if os(macOS)
        .preference(key: MinimumWindowWidthKey.self, value: minimumSplitWidth)
        .background(WindowFinder(window: $window))
        .onChange(of: minimumSplitWidth, initial: true) { widenWindowToFit() }
        .onChange(of: window) { widenWindowToFit() }
        .onChange(of: columnVisibility) { _, visibility in
            UserDefaults.standard.set(
                visibility == .detailOnly, forKey: UserDefaultKeys.deviceSidebarHidden)
        }
        #endif
        .onAppear {
            if scanIPV4Actor == nil { scanIPV4Actor = DeviceDiscoveryActor() }
            if scanSSDPActor == nil { scanSSDPActor = DeviceDiscoveryActor() }
        }
        // The sidebar shows every device at once, but only the selected one
        // refreshes its own record - probe the rest so their dots mean something.
        .probingDeviceLiveness(deviceIds, isActive: scenePhase != .background)
        // Restore the last-viewed device rather than falling to the top of the
        // list, and re-pick only when the remembered one is actually gone.
        .task(id: deviceIds) {
            do {
                try await RoamDataHandler.shared.ensureValidPrimaryDevice()
            } catch {
                Log.userInteraction.error(
                    "Error selecting an initial device \(error, privacy: .public)")
            }
        }
    }

    #if os(macOS)
    private func widenWindowToFit() {
        guard let window, let minimumSplitWidth else { return }
        let contentWidth = window.contentRect(forFrameRect: window.frame).width
        guard contentWidth < minimumSplitWidth else { return }

        // Grow toward the sidebar's side, staying on screen.
        var frame = window.frame
        let growth = minimumSplitWidth - contentWidth
        frame.origin.x -= growth
        frame.size.width += growth
        if let visible = window.screen?.visibleFrame, frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        window.setFrame(frame, display: true, animate: true)
    }
    #endif

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
            DeviceSidebarFooter(deviceCount: deviceIds.count)
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
#if os(macOS)
struct MinimumWindowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
#endif
#endif
