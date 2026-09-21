#if os(iOS)
import SwiftUI
import UIKit

/// A sidebar with one remote on the inner display, or a swipe pager pushed
/// from the compact device grid. Selection survives changes between modes.
struct PhoneDeviceDetailPager: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    @AppStorage(UserDefaultKeys.phoneSidebarHidden) private var sidebarHidden = false

    let allDeviceIds: [String]
    let unreadMessages: Int
    let usesSidebar: Bool
    let onScan: () async -> Void
    let onBackToHome: (() -> Void)?

    @Binding private var selectedDeviceId: String?
    @State private var sidebarDropTargetId: String?
    // The page order is frozen at push time. `allDeviceIds` reorders itself
    // underneath us - discovery inserts new devices at the front, and the
    // "recently used" sort moves whatever page the user lands on to the top -
    // and letting that reach the ForEach would slide pages sideways under the
    // user's thumb. Only membership changes are reconciled; see `syncPages`.
    @State private var pagerDeviceIds: [String]
    @State private var showKeyboard: Bool = CommandLine.arguments.contains("-OpenKeyboard")
    @State private var isInteractivelyPopping: Bool = false
    @State private var isAppsScrolling: Bool = false
    @State private var lastPagerWidth: CGFloat = 0
    // The ScrollView's `.scrollPosition` binding. Held separately from
    // `selectedDeviceId` so we can briefly drive it to `nil` and back on
    // width changes to force a re-snap to the current page (otherwise
    // rotation leaves the page half-scrolled at the old pixel offset).
    @State private var scrollPositionId: String?
    // Debounces the re-snap so we don't fire mid-rotation when the
    // PreferenceKey reports each intermediate width - wait for the
    // animation to settle, then snap once.
    @State private var resnapTask: Task<Void, Never>?
    // Kept in state so the toolbar waits until the sidebar geometry is ready.
    @State private var sidebarRoom: CGFloat?
    // Whether the bottom bar stands along the trailing edge, as it does on
    // the outer display held sideways. The axis is only readable from inside
    // toolbar content, so the keyboard item reports it here.
    @State private var toolbarIsVertical = false
    // Global frame of the empty slot a vertical bar reserves for the page
    // dots, so the capsule drawn over it lines up in every posture.
    @State private var dotsSlotFrame: CGRect?
    // First page shown by the page dots. Shared by every place the dots are
    // drawn so the window does not jump when the bar changes axis.
    @State private var dotsWindowStart = 0

    init(
        selectedDeviceId: Binding<String?>,
        allDeviceIds: [String],
        unreadMessages: Int,
        usesSidebar: Bool,
        onScan: @escaping () async -> Void,
        onBackToHome: (() -> Void)? = nil
    ) {
        self.usesSidebar = usesSidebar
        self.onScan = onScan
        self.allDeviceIds = allDeviceIds
        self.unreadMessages = unreadMessages
        self.onBackToHome = onBackToHome
        _selectedDeviceId = selectedDeviceId
        _scrollPositionId = State(initialValue: selectedDeviceId.wrappedValue)
        _pagerDeviceIds = State(initialValue: allDeviceIds)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if showsSidebar, let sidebarRoom {
                    deviceSidebar
                        .frame(width: sidebarRoom)
                        .ignoresSafeArea(.container, edges: proxy.size.width > proxy.size.height ? [] : .top)
                        .transition(.move(edge: .leading))
                }
                if usesSidebar {
                    if let selectedDeviceId {
                        PhoneDetailPage(
                            deviceId: selectedDeviceId,
                            unreadMessages: unreadMessages,
                            isActive: true,
                            externalShowKeyboard: $showKeyboard
                        )
                        .id(selectedDeviceId)
                    } else {
                        ContentUnavailableView(
                            String(localized: "Scanning for devices"),
                            systemImage: "rays"
                        )
                    }
                } else {
                    pager
                }
            }
            .overlay { verticalBarDots }
            // An AppStorage write lands through UserDefaults observation,
            // outside the toggle's withAnimation transaction, so the
            // animation is keyed to the value instead.
            .animation(.snappy, value: showsSidebar)
            .onChange(of: sidebarWidth(in: proxy), initial: true) { _, width in
                sidebarRoom = width
            }
        }
        // When the keyboard-entry overlay's text field becomes first
        // responder, let the system keyboard push the pager content up so
        // the entry floats above the keyboard. Otherwise the keyboard
        // would cover the field. While the keyboard is hidden, ignore its
        // safe area so layout stays stable.
        .ignoresSafeArea(.keyboard, edges: showKeyboard ? [] : .all)
        .toolbar(.hidden, for: .navigationBar)
        .applyBuilder {
            if #available(iOS 26.0, *) {
                // Hidden while the on-screen keyboard is up so the bar doesn't
                // sit between the user and the keys.
                $0
                    .toolbar { pagerToolbar }
                    .toolbar(showKeyboard ? .hidden : .visible, for: .bottomBar)
            } else {
                $0
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !showKeyboard {
                            floatingButtonBar
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, -10)
                                // Without this, SwiftUI applies its default slow fade to
                                // the inset when the pager appears via the zoom
                                // transition, stretching it long after the zoom ends.
                                .transaction { $0.animation = nil }
                        }
                    }
                    .toolbar(.hidden, for: .bottomBar)
            }
        }
        // While the user is interactively swiping back to the home grid,
        // disable hit-testing so taps that visually appear to land on the
        // revealed home view don't actually press remote buttons.
        .allowsHitTesting(!isInteractivelyPopping)
        .background(InteractivePopObserver { isInteractivelyPopping = $0 })
        .onChange(of: allDeviceIds) { _, newIds in
            syncPages(with: newIds)
        }
        .onChange(of: selectedDeviceId, initial: true) { _, newId in
            scrollPositionId = newId
            guard let newId else { return }
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

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pagerDeviceIds, id: \.self) { deviceId in
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
    }

    // MARK: - Sidebar

    private var sidebarAvailable: Bool {
        usesSidebar && sidebarRoom != nil
    }

    private var showsSidebar: Bool {
        sidebarAvailable && !sidebarHidden
    }

    /// A vertical fold reserves the first panel so remote controls stay
    /// clear of the crease. Flat layouts use a compact sidebar in either orientation.
    private func sidebarWidth(in proxy: GeometryProxy) -> CGFloat {
        if #available(iOS 27.1, *),
            let fold = proxy.reservedRegions(kind: .division).first,
            fold.frame.height > fold.frame.width
        {
            return fold.frame.maxX
        }
        return min(240, proxy.size.width * 0.3)
    }

    private var deviceSidebar: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(allDeviceIds, id: \.self) { deviceId in
                    Button {
                        withAnimation(.snappy) { selectedDeviceId = deviceId }
                    } label: {
                        DeviceSidebarCard(deviceId: deviceId)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(deviceId == selectedDeviceId
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                        : AnyShapeStyle(.regularMaterial))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("SidebarDevice_\(deviceId)")
                    .accessibilityAddTraits(deviceId == selectedDeviceId ? .isSelected : [])
                    .deviceActions(
                        deviceId: deviceId,
                        deviceName: nil,
                        onEdit: { appDelegate.navigationPath.showEditDevice = deviceId }
                    )
                    .overlay {
                        if sidebarDropTargetId == deviceId {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .draggable(deviceId)
                    .dropDestination(for: String.self) { items, _ in
                        sidebarDropTargetId = nil
                        guard let draggedId = items.first else { return false }
                        return moveSidebarDevice(draggedId, toPositionOf: deviceId)
                    } isTargeted: { isTargeted in
                        withAnimation(.snappy) {
                            if isTargeted {
                                sidebarDropTargetId = deviceId
                            } else if sidebarDropTargetId == deviceId {
                                sidebarDropTargetId = nil
                            }
                        }
                    }
                }
            }
            .animation(.snappy, value: allDeviceIds)
            .padding(.horizontal, 12)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DeviceSidebarFooter(deviceCount: allDeviceIds.count)
        }
        .refreshable { await onScan() }
        .background(.background.secondary)
    }

    private func moveSidebarDevice(_ draggedId: String, toPositionOf targetId: String) -> Bool {
        guard draggedId != targetId,
            let from = allDeviceIds.firstIndex(of: draggedId),
            let to = allDeviceIds.firstIndex(of: targetId)
        else {
            return false
        }

        // The insertion offset uses indices from before the source is removed.
        let destination = to > from ? to + 1 : to
        Task {
            do {
                try await RoamDataHandler.shared.reorderDevices(
                    fromOffsets: IndexSet(integer: from), toOffset: destination)
            } catch {
                Log.userInteraction.error("Error reordering sidebar devices \(error, privacy: .public)")
            }
        }
        return true
    }

    /// Reconciles the frozen page order with the live device list: devices
    /// that went away are dropped and new ones are appended at the end, but
    /// the pages already on screen keep the positions the user learned.
    private func syncPages(with newIds: [String]) {
        guard Set(newIds) != Set(pagerDeviceIds) else { return }
        var next = pagerDeviceIds.filter(newIds.contains)
        next.append(contentsOf: newIds.filter { !next.contains($0) })
        pagerDeviceIds = next
    }

    /// On a real width change (rotation, split-view resize) the paged
    /// scroll view keeps its old pixel offset, which leaves the current
    /// page half-scrolled. Wait for the rotation animation to settle,
    /// then drive the position binding through a `nil → selected`
    /// re-snap to force a clean alignment. The PreferenceKey fires
    /// multiple times as the layout interpolates, so cancel any
    /// in-flight task on each new value and only the last one runs.
    private func handleWidthChange(_ newWidth: CGFloat) {
        guard newWidth > 0 else { return }
        let previousWidth = lastPagerWidth
        lastPagerWidth = newWidth
        guard previousWidth > 0, abs(newWidth - previousWidth) > 1 else { return }
        let target = selectedDeviceId
        resnapTask?.cancel()
        resnapTask = Task { @MainActor in
            // Wait past the iOS rotation animation (~0.3s) plus a small
            // buffer so the LazyHStack has settled into the new page
            // widths before we ask the scroll view to snap.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            scrollPositionId = nil
            // One runloop tick so SwiftUI registers the change before
            // we set it back to the target.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            scrollPositionId = target
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var pagerToolbar: some ToolbarContent {
        if sidebarAvailable {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    sidebarHidden.toggle()
                } label: {
                    Label(
                        String(
                            localized: "Devices",
                            comment: "Accessibility label for the toolbar button that shows or hides the device sidebar on iPhone Duo"
                        ),
                        systemImage: "sidebar.left"
                    )
                }
                .accessibilityIdentifier("SidebarButton")
                .tint(.primary)
            }
        }
        ToolbarItem(placement: .bottomBar) {
            ToolbarAxisReader { isVertical in
                Button {
                    withAnimation { showKeyboard.toggle() }
                } label: {
                    Label(keyboardTitle, systemImage: "keyboard")
                }
                .accessibilityIdentifier("KeyboardButton")
                .tint(.primary)
                .onChange(of: isVertical, initial: true) { _, isVertical in
                    toolbarIsVertical = isVertical
                }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if !usesSidebar, pagerDeviceIds.count > 1, !toolbarIsVertical {
            ToolbarItem(placement: .bottomBar) {
                pageDots
                    .padding(.horizontal, 6)
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }
        ToolbarItem(placement: .bottomBar) {
            if usesSidebar {
                settingsButton
            } else {
                Button {
                    onBackToHome?()
                } label: {
                    Label(allDevicesTitle, systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("AllDevicesButton")
                .tint(.primary)
            }
        }
        if !usesSidebar, pagerDeviceIds.count > 1, toolbarIsVertical, #available(iOS 27.1, *) {
            // The dots stay horizontal, which a vertical bar cannot hold, so
            // the bar ends with an empty slot below the last button and
            // `verticalBarDots` draws the capsule over it.
            ToolbarItem(placement: .bottomBar) {
                Color.clear
                    .frame(width: 44, height: 44)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        dotsSlotFrame = frame
                    }
            }
            .axisBehavior(.verticalPreferred)
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// The page dots for a vertical bar: a capsule as tall as the bar's
    /// buttons, ending at the reserved slot's trailing edge and extending
    /// left over the page.
    @ViewBuilder
    private var verticalBarDots: some View {
        if !usesSidebar, toolbarIsVertical, pagerDeviceIds.count > 1, let slot = dotsSlotFrame {
            GeometryReader { proxy in
                let bounds = proxy.frame(in: .global)
                pageDotsOverlay
                    .frame(height: slot.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, bounds.maxX - slot.maxX)
                    .padding(.bottom, bounds.maxY - slot.maxY)
            }
            .ignoresSafeArea()
        }
    }

    private var keyboardTitle: String {
        String(
            localized: "Keyboard",
            comment: "Accessibility label for the floating keyboard toggle on iPhone detail"
        )
    }

    private var settingsButton: some View {
        Button {
            appDelegate.navigationPath.append(.settingsDestination(.global))
        } label: {
            Label(String(localized: "Settings"), systemImage: "gear")
        }
        .accessibilityIdentifier("SettingsButton")
        .tint(.primary)
    }

    private var allDevicesTitle: String {
        String(
            localized: "All devices",
            comment: "Accessibility label for the floating button that returns to the device grid"
        )
    }

    private var pageDots: some View {
        PageDots(
            count: pagerDeviceIds.count,
            selectedIndex: pagerDeviceIds.firstIndex(where: { $0 == selectedDeviceId }) ?? 0,
            windowStart: $dotsWindowStart
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageIndicatorAccessibility)
    }

    private var floatingButtonBar: some View {
        HStack(spacing: 12) {
            keyboardButton
            Spacer()
            if !usesSidebar, pagerDeviceIds.count > 1 {
                pageIndicator
            }
            if usesSidebar {
                settingsButton
            } else {
                allDevicesButton
            }
        }
    }

    private var pageIndicator: some View {
        pageDots
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .glassEffectIfSupported(in: Capsule())
    }

    private var pageDotsOverlay: some View {
        pageDots
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial, in: Capsule())
            .glassEffectIfSupported(in: Capsule())
    }

    private var pageIndicatorAccessibility: String {
        guard let idx = pagerDeviceIds.firstIndex(where: { $0 == selectedDeviceId }) else {
            return ""
        }
        return String(
            format: String(
                localized: "Page %d of %d",
                comment: "Accessibility label for the iPhone detail pager indicator. First int is the current page, second is the total."
            ),
            idx + 1,
            pagerDeviceIds.count
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
        .accessibilityLabel(keyboardTitle)
    }

    private var allDevicesButton: some View {
        Button {
            onBackToHome?()
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .glassEffectIfSupported(tint: Color.accentColor.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AllDevicesButton")
        .accessibilityLabel(allDevicesTitle)
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

/// Up to five dots for a horizontally paged view. Past five pages a window
/// slides to keep the selection inside it, and an edge dot shrinks when
/// pages continue beyond it.
private struct PageDots: View {
    static let windowSize = 5
    static let dotSize: CGFloat = 7
    static let edgeDotSize: CGFloat = 4

    let count: Int
    let selectedIndex: Int
    @Binding var windowStart: Int

    var body: some View {
        // Clamp locally: `count` can shrink before `onChange` has moved the
        // window, and a range with start past end would trap.
        let start = min(max(windowStart, 0), max(count - Self.windowSize, 0))
        let end = min(start + Self.windowSize, count)
        HStack(spacing: 8) {
            ForEach(start..<end, id: \.self) { index in
                let continuesBefore = index == start && start > 0
                let continuesAfter = index == end - 1 && end < count
                let size = continuesBefore || continuesAfter ? Self.edgeDotSize : Self.dotSize
                Circle()
                    .fill(index == selectedIndex ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(width: size, height: size)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedIndex)
        .animation(.easeInOut(duration: 0.2), value: start)
        .onChange(of: selectedIndex, initial: true) { _, index in
            windowStart = Self.windowStart(containing: index, from: windowStart, count: count)
        }
        .onChange(of: count) { _, count in
            windowStart = Self.windowStart(containing: selectedIndex, from: windowStart, count: count)
        }
    }

    /// Moves the window only when the selection lands on an edge dot that
    /// has pages beyond it, so paging within the window leaves it still.
    static func windowStart(containing selected: Int, from start: Int, count: Int) -> Int {
        let maxStart = count - windowSize
        guard maxStart > 0 else { return 0 }
        let start = min(max(start, 0), maxStart)
        let firstFull = start + (start > 0 ? 1 : 0)
        let lastFull = start + windowSize - 1 - (start < maxStart ? 1 : 0)
        if selected < firstFull {
            return max(selected - 1, 0)
        }
        if selected > lastFull {
            return min(selected - (windowSize - 2), maxStart)
        }
        return start
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
