#if os(iOS)
import SwiftUI
import UIKit

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
    @State private var isInteractivelyPopping: Bool = false
    @State private var isAppsScrolling: Bool = false
    @State private var lastPagerWidth: CGFloat = 0
    // The ScrollView's `.scrollPosition` binding. Held separately from
    // `selectedDeviceId` so we can briefly drive it to `nil` and back on
    // width changes to force a re-snap to the current page (otherwise
    // rotation leaves the page half-scrolled at the old pixel offset).
    @State private var scrollPositionId: String?

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
        _scrollPositionId = State(initialValue: startingDeviceId)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(allDeviceIds, id: \.self) { deviceId in
                    PhoneDetailPage(
                        deviceId: deviceId,
                        unreadMessages: unreadMessages,
                        isActive: deviceId == selectedDeviceId,
                        externalShowKeyboard: $showKeyboard
                    )
                    .id(deviceId)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPositionId)
        .scrollDisabled(isAppsScrolling)
        .onPreferenceChange(AppsScrollingPreferenceKey.self) { newValue in
            isAppsScrolling = newValue
        }
        .onChange(of: scrollPositionId) { _, newValue in
            if let newValue, newValue != selectedDeviceId {
                selectedDeviceId = newValue
            }
        }
        // When the layout width changes (typically on rotation), the paged
        // ScrollView keeps its pixel offset, which leaves the current page
        // half-scrolled. Drive the position to `nil` and then back to the
        // selected device on the next runloop tick so the scroll view
        // re-snaps cleanly.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PagerWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(PagerWidthKey.self) { newWidth in
            handleWidthChange(newWidth)
        }
        // When the keyboard-entry overlay's text field becomes first
        // responder, let the system keyboard push the pager content up so
        // the entry floats above the keyboard. Otherwise the keyboard
        // would cover the field. While the keyboard is hidden, ignore its
        // safe area so layout stays stable.
        .ignoresSafeArea(.keyboard, edges: showKeyboard ? [] : .all)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Suppress the bottom button bar while the on-screen keyboard
            // is up so it doesn't sit between the user and the keys; the
            // tap-to-dismiss area inside `keyboardEntryOverlay` is enough
            // to close the keyboard.
            if !showKeyboard {
                floatingButtonBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, -10)
                    // Without this, SwiftUI applies its default slow fade to the
                    // safeAreaInset content when the destination view appears
                    // via .navigationTransition(.zoom), which extends the
                    // perceived transition long after the zoom has finished.
                    .transaction { $0.animation = nil }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .bottomBar)
        // While the user is interactively swiping back to the home grid,
        // disable hit-testing so taps that visually appear to land on the
        // revealed home view don't actually press remote buttons.
        .allowsHitTesting(!isInteractivelyPopping)
        .background(InteractivePopObserver { isInteractivelyPopping = $0 })
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

    /// On a real width change (rotation, split-view resize) the paged
    /// scroll view keeps its old pixel offset, which leaves the current
    /// page half-scrolled. Drive the position binding through a one-tick
    /// nil → selected re-snap to force a clean alignment.
    private func handleWidthChange(_ newWidth: CGFloat) {
        guard newWidth > 0 else { return }
        let previousWidth = lastPagerWidth
        lastPagerWidth = newWidth
        guard previousWidth > 0, abs(newWidth - previousWidth) > 1 else { return }
        let target = selectedDeviceId
        scrollPositionId = nil
        DispatchQueue.main.async {
            scrollPositionId = target
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
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
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
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
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
    let isActive: Bool
    @Binding var externalShowKeyboard: Bool

    @State private var deviceLoader: DeviceLoader

    init(deviceId: String, unreadMessages: Int, isActive: Bool, externalShowKeyboard: Binding<Bool>) {
        self.deviceId = deviceId
        self.unreadMessages = unreadMessages
        self.isActive = isActive
        self._externalShowKeyboard = externalShowKeyboard
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    var body: some View {
        RemoteViewContained(
            device: deviceLoader.device,
            unreadMessages: unreadMessages,
            externalShowKeyboard: $externalShowKeyboard,
            hidesKeyboardToolbarButton: true,
            isActive: isActive
        )
    }
}

/// Propagates the pager's current laid-out width up to the parent so it
/// can detect rotation/resize and force the paged scroll view to re-snap
/// to the current page.
private struct PagerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Surfaces UIKit's interactive-pop state into SwiftUI by embedding a
/// near-empty child view controller. When the host's `viewWillDisappear`
/// fires with an interactive transition coordinator, the swipe-back is
/// in progress; we report `true` and listen for cancellation to flip back.
private struct InteractivePopObserver: UIViewControllerRepresentable {
    var onChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> Observer {
        let vc = Observer()
        vc.onChange = onChange
        return vc
    }

    func updateUIViewController(_ uiViewController: Observer, context: Context) {
        uiViewController.onChange = onChange
    }

    final class Observer: UIViewController {
        var onChange: ((Bool) -> Void)?

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let coordinator = transitionCoordinator, coordinator.isInteractive else {
                return
            }
            onChange?(true)
            coordinator.notifyWhenInteractionChanges { [weak self] context in
                if context.isCancelled {
                    self?.onChange?(false)
                }
            }
        }
    }
}
#endif
