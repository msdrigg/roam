#if os(iOS)
import SwiftUI

/// iPhone-only root: a vertical card grid of devices, with a `...` menu,
/// pull-to-refresh rescan, and an unprominent "Add device manually" footer.
///
/// Tapping a card pushes `PhoneDeviceDetailPager` on a local `NavigationStack`.
/// On iOS 18+ the push uses a `.zoom` matched-transition for the Weather-style
/// effect; older OSes fall back to a default push.
///
/// On first appear, if there is already a primary device, the pager is pushed
/// automatically so the app opens to the last-viewed remote.
struct PhoneHomeView: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @State private var devicesLoader = DeviceListLoader(dataHandler: .shared)
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    @State private var path: [String] = []
    @State private var didAutoOpenPrimary = false
    @State private var scanIPV4Actor: DeviceDiscoveryActor?
    @State private var scanSSDPActor: DeviceDiscoveryActor?

    @Namespace private var cardNamespace

    private var deviceIds: [String] { devicesLoader.devices ?? [] }
    private var isEmpty: Bool { devicesLoader.devices != nil && deviceIds.isEmpty }
    private var unreadMessages: Int { messageLoader.unreadCount }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(String(
                    localized: "Devices",
                    comment: "Title of the iPhone home screen listing all devices"
                ))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            appDelegate.navigationPath.showAddDevice = true
                        } label: {
                            Label(
                                String(
                                    localized: "Add a device manually",
                                    comment: "Bottom-bar button on iPhone home to manually add a device"
                                ),
                                systemImage: "plus"
                            )
                            .labelStyle(.titleAndIcon)
                        }
                        .accessibilityIdentifier("AddDeviceButton")

                        Spacer()

                        Button {
                            appDelegate.navigationPath.append(.settingsDestination(.global))
                        } label: {
                            Label(
                                String(localized: "Settings", comment: "Bottom-bar button on iPhone home to open Settings"),
                                systemImage: "gear"
                            )
                        }
                        .accessibilityIdentifier("SettingsButton")
                    }
                }
                .navigationDestination(for: String.self) { deviceId in
                    detailDestination(for: deviceId)
                }
                .customAccentColorTint()
        }
        .onAppear {
            if scanIPV4Actor == nil { scanIPV4Actor = DeviceDiscoveryActor() }
            if scanSSDPActor == nil { scanSSDPActor = DeviceDiscoveryActor() }
        }
        .onChange(of: primaryDeviceLoader.device?.id, initial: true) { _, newId in
            guard !didAutoOpenPrimary, let newId, !newId.isEmpty else { return }
            didAutoOpenPrimary = true
            if path.isEmpty {
                path = [newId]
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            emptyContent
        } else {
            deviceGrid
        }
    }

    private var deviceGrid: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(deviceIds, id: \.self) { deviceId in
                    deviceCardButton(for: deviceId)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await runManualScan() }
    }

    @ViewBuilder
    private func deviceCardButton(for deviceId: String) -> some View {
        let card = DeviceSidebarCard(deviceId: deviceId)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .deviceActions(
                deviceId: deviceId,
                deviceName: nil,
                onEdit: { appDelegate.navigationPath.showEditDevice = deviceId }
            )

        Button {
            if path.last != deviceId {
                path.append(deviceId)
            }
        } label: {
            if #available(iOS 18.0, *) {
                card.matchedTransitionSource(id: deviceId, in: cardNamespace)
            } else {
                card
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DeviceCard_\(deviceId)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
    }

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Label(
                    String(
                        localized: "Scanning for devices",
                        comment: "Empty-state heading on iPhone home while no devices have been discovered"
                    ),
                    systemImage: "rays"
                )
                .labelStyle(.titleAndIcon)
                .font(.title3)
                .symbolEffect(.variableColor)
                .padding()
                .glowing()

                Text(
                    "Roam will list Roku devices on your network as they're found.",
                    comment: "Empty-state caption on iPhone home explaining auto-discovery"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await runManualScan() }
    }

    // MARK: - Navigation destination

    @ViewBuilder
    private func detailDestination(for deviceId: String) -> some View {
        let pager = PhoneDeviceDetailPager(
            startingDeviceId: deviceId,
            allDeviceIds: deviceIds,
            unreadMessages: unreadMessages,
            onBackToHome: { path.removeAll() }
        )

        if #available(iOS 18.0, *) {
            pager.navigationTransition(.zoom(sourceID: deviceId, in: cardNamespace))
        } else {
            pager
        }
    }

    // MARK: - Scanning

    private func runManualScan() async {
        guard let scanIPV4Actor, let scanSSDPActor else { return }
        await performManualDeviceScan(ipv4Actor: scanIPV4Actor, ssdpActor: scanSSDPActor)
    }
}
#endif
