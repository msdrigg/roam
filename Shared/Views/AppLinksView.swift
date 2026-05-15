import SwiftUI

#if os(visionOS)
    let globalGridWidth: CGFloat = 100
    let globalGridSpacing: CGFloat = 20
    let globalGridRowSpacing: CGFloat = 20
    let globalGridHeightWithApps: CGFloat = 145
#elseif os(iOS)
    let globalGridWidth: CGFloat = 70
    let globalGridSpacing: CGFloat = 10
    let globalGridRowSpacing: CGFloat = 10
    let globalGridHeightWithApps: CGFloat = 92
#else
    let globalGridWidth: CGFloat = 52
    let globalGridSpacing: CGFloat = 10
    let globalGridRowSpacing: CGFloat = 2
    let globalGridHeightWithApps: CGFloat = 72
#endif

struct AppLinksView: View {
    var handleOpenApp: (AppLink) -> Void
    let rows: Int
    let deviceId: String?

    init(handleOpenApp: @escaping (AppLink) -> Void, rows: Int, deviceId: String?) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        self.deviceId = deviceId
        self._appLoader = State(initialValue: Self.makeAppLoader(deviceId: deviceId))
    }

    @State private var appLoader: DeviceAppsLoader?
    // Remember whether the previous device had apps so we don't collapse the
    // grid back to zero height while a new device's apps are still loading.
    @State private var lastKnownHasApps: Bool = false

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth
    @ScaledMetric var gridSpacing: CGFloat = globalGridSpacing
    @ScaledMetric var gridRowSpacing: CGFloat = globalGridRowSpacing
    @ScaledMetric var populatedGridHeightScaled: CGFloat = globalGridHeightWithApps

    var appLinks: [AppLink] {
        appLoader?.apps ?? []
    }

    private var confirmedHasApps: Bool? {
        guard let apps = appLoader?.apps else { return nil }
        return !apps.isEmpty
    }

    private var shouldShowApps: Bool {
        confirmedHasApps ?? lastKnownHasApps
    }

    var gridHeight: CGFloat {
        shouldShowApps ? populatedGridHeightScaled : 1
    }

    var totalGridHeight: CGFloat {
        if !shouldShowApps {
            return gridHeight
        } else {
            return gridHeight * CGFloat(rows) + gridRowSpacing * CGFloat(max(rows - 1, 0))
        }
    }

    @Namespace var linkAnimation

    @MainActor
    init(deviceId: String?, rows: Int, handleOpenApp: @escaping ( AppLink) -> Void) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        self.deviceId = deviceId
        self._appLoader = State(initialValue: Self.makeAppLoader(deviceId: deviceId))
    }

    @MainActor
    private static func makeAppLoader(deviceId: String?) -> DeviceAppsLoader? {
        guard let deviceId else { return nil }
        return DeviceAppsLoader(deviceId: deviceId, dataHandler: RoamDataHandler.shared)
    }

    var body: some View {
        GeometryReader { geometry in
            if !appLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Spacer()
                    LazyHGrid(
                        rows: Array(
                            repeating: GridItem(.fixed(CGFloat(gridHeight)), spacing: gridRowSpacing),
                            count: rows
                        ),
                        spacing: gridSpacing
                    ) {
                        ForEach(Array(appLinks.enumerated()), id: \.element.id) { _, app in
                            AppLinkButton(
                                app: app,
                                action: handleOpenApp
                            )
                                .scrollTransition(.interactive) { content, phase in
                                    content
                                        .scaleEffect(phase != .identity ? 0.7 : 1)
                                        .opacity(phase != .identity ? 0.5 : 1)
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .frame(
                        minWidth: geometry.frame(in: .global).width,
                        minHeight: geometry.frame(in: .global).height
                    )
#if os(macOS)
                    .captureVerticalScrollWheel()
#endif
                    Spacer()
                }
                .scrollClipDisabled()
                .safeAreaPadding(.horizontal, 4)
#if os(iOS)
                // Claim horizontal drags inside this ScrollView so the
                // enclosing paging TabView doesn't steal them at content
                // edges. Bouncing/overscroll on the inner stays default.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                )
#endif
            }
        }
            .onChange(of: deviceId) { _, newDeviceId in
                appLoader = Self.makeAppLoader(deviceId: newDeviceId)
            }
            .onChange(of: confirmedHasApps) { _, newValue in
                if let newValue {
                    lastKnownHasApps = newValue
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(height: totalGridHeight)
            .animation(.default, value: shouldShowApps)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppLinkButton: View {
    let app: AppLink
    let action: ( AppLink) -> Void

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth

    private var appButtonSpacing: CGFloat {
        #if os(macOS)
        return 3
        #else
        return 8
        #endif
    }

    var body: some View {
        Button(action: {
            action(app)
        }, label: {
            VStack(spacing: appButtonSpacing) {
                FallibleImage(from: app.iconURL, fallback: "questionmark.app.fill", maxSize: gridWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: gridWidth)
                    .shadow(radius: 4)

                Text(app.name)
                #if os(macOS)
                    .font(.caption2)
                #elseif os(visionOS)
                    .font(.body)
                #else
                    .font(.caption)
                #endif
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .frame(maxWidth: gridWidth)
            }
        })
        .appLinkButtonStyle()
    }
}

private extension View {
    @ViewBuilder
    func appLinkButtonStyle() -> some View {
        self.buttonStyle(.plain)
    }
}

#if DEBUG
#Preview(
    "App Links",
    traits: .sampleData, .fixedLayout(width: 400, height: 300)
) {
    AppLinksView(deviceId: nil, rows: 2, handleOpenApp: { _ in })
        .padding(.bottom, 10)
        .padding(.horizontal, 10)
}
#endif
