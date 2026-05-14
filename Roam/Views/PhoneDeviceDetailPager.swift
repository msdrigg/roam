#if os(iOS)
import SwiftUI

/// iPhone detail screen pushed from `PhoneHomeView`.
///
/// Renders all configured devices as horizontally-swipeable pages, each
/// hosting `RemoteViewContained`. Selection drives the primary device so
/// the home grid reflects the same "last-viewed" state.
///
/// The navigation bar is hidden — the user navigates back to the grid via
/// the leftmost-edge swipe-back gesture or the floating "all devices" button
/// in the bottom-right. The keyboard is toggled by a floating bottom-left
/// button so it stays put while pages are being swiped (instead of riding
/// along with the per-page nav bar).
struct PhoneDeviceDetailPager: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    let startingDeviceId: String
    let allDeviceIds: [String]
    let unreadMessages: Int
    let onBackToHome: () -> Void

    @State private var selectedDeviceId: String
    @State private var showKeyboard: Bool = false

    init(
        startingDeviceId: String,
        allDeviceIds: [String],
        unreadMessages: Int,
        onBackToHome: @escaping () -> Void
    ) {
        self.startingDeviceId = startingDeviceId
        self.allDeviceIds = allDeviceIds
        self.unreadMessages = unreadMessages
        self.onBackToHome = onBackToHome
        _selectedDeviceId = State(initialValue: startingDeviceId)
    }

    var body: some View {
        TabView(selection: $selectedDeviceId) {
            ForEach(allDeviceIds, id: \.self) { deviceId in
                PhoneDetailPage(
                    deviceId: deviceId,
                    unreadMessages: unreadMessages,
                    externalShowKeyboard: $showKeyboard
                )
                .padding(.top, 24)
                .tag(deviceId)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingButtonBar
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .bottomBar)
        .onChange(of: selectedDeviceId) { _, newId in
            Task {
                do {
                    try await RoamDataHandler.shared.makePrimaryDevice(id: newId)
                } catch {
                    Log.userInteraction.error(
                        "Error setting selected device from pager \(error, privacy: .public)")
                }
            }
        }
    }

    private var floatingButtonBar: some View {
        HStack {
            keyboardButton
            Spacer()
            if allDeviceIds.count > 1 {
                pageIndicator
                Spacer()
            }
            allDevicesButton
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(allDeviceIds, id: \.self) { deviceId in
                Circle()
                    .fill(deviceId == selectedDeviceId ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: selectedDeviceId)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .glassEffectIfSupported(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageIndicatorAccessibility)
    }

    private var pageIndicatorAccessibility: String {
        guard let idx = allDeviceIds.firstIndex(of: selectedDeviceId) else {
            return ""
        }
        return String(
            format: String(
                localized: "Page %d of %d",
                comment: "Accessibility label for the iPhone detail pager indicator. First int is the current page, second is the total."
            ),
            idx + 1,
            allDeviceIds.count
        )
    }

    private var keyboardButton: some View {
        Button {
            withAnimation { showKeyboard.toggle() }
        } label: {
            Image(systemName: "keyboard")
                .font(.title3)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("KeyboardButton")
        .accessibilityLabel(String(
            localized: "Keyboard",
            comment: "Accessibility label for the floating keyboard toggle on iPhone detail"
        ))
    }

    private var allDevicesButton: some View {
        Button {
            onBackToHome()
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            localized: "All devices",
            comment: "Accessibility label for the floating button that returns to the device grid"
        ))
    }
}

private struct PhoneDetailPage: View {
    let deviceId: String
    let unreadMessages: Int
    @Binding var externalShowKeyboard: Bool

    @State private var deviceLoader: DeviceLoader

    init(deviceId: String, unreadMessages: Int, externalShowKeyboard: Binding<Bool>) {
        self.deviceId = deviceId
        self.unreadMessages = unreadMessages
        self._externalShowKeyboard = externalShowKeyboard
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    var body: some View {
        RemoteViewContained(
            device: deviceLoader.device,
            unreadMessages: unreadMessages,
            externalShowKeyboard: $externalShowKeyboard,
            hidesKeyboardToolbarButton: true
        )
    }
}
#endif
