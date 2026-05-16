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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    simulatedBottomBar
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
            // Defer the push so the LazyVStack has a layout pass to register the
            // primary card's matchedTransitionSource; otherwise the very first
            // interactive swipe-back has no source and falls back to a default pop.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if path.isEmpty {
                    path = [newId]
                }
            }
        }
    }

    // MARK: - Simulated bottom bar
    //
    // A custom view in the bottom safe area replaces the native `.bottomBar`
    // toolbar so the buttons can carry a real liquid-glass effect rather than
    // the default toolbar chrome. Because the inset lives inside `content`,
    // it naturally fades in alongside the `.navigationTransition(.zoom)`
    // pop from `PhoneDeviceDetailPager` — we intentionally don't suppress
    // that fade so the buttons settle in with the zoom.

    private var simulatedBottomBar: some View {
        VStack(spacing: 0) {
            // Connectivity / permission warnings live above the bottom bar so
            // they stay pinned in place while the device grid scrolls.
            NetworkConnectivityBanner()
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            bottomBarButtons
        }
    }

    private var bottomBarButtons: some View {
        HStack(spacing: 12) {
            Button {
                appDelegate.navigationPath.showAddDevice = true
            } label: {
                Label(
                    String(
                        localized: "Add device manually",
                        comment: "Bottom-bar button on iPhone home to manually add a device"
                    ),
                    systemImage: "plus"
                )
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddDeviceButton")

            Spacer()

            Button {
                appDelegate.navigationPath.append(.settingsDestination(.global))
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SettingsButton")
            .accessibilityLabel(String(
                localized: "Settings",
                comment: "Bottom-bar button on iPhone home to open Settings"
            ))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, -10)
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
