import SwiftUI

#if os(visionOS)
    let globalGridWidth: CGFloat = 100
    let globalGridSpacing: CGFloat = 20
    let globalGridHeight: CGFloat = 130
#elseif os(iOS)
    let globalGridWidth: CGFloat = 70
    let globalGridSpacing: CGFloat = 10
    let globalGridHeight: CGFloat = 80
#else
    let globalGridWidth: CGFloat = 60
    let globalGridSpacing: CGFloat = 10
    let globalGridHeight: CGFloat = 70
#endif

struct AppLinksView: View {
    var handleOpenApp: (AppLink) -> Void
    let rows: Int
    let deviceId: String?

    init(handleOpenApp: @escaping (AppLink) -> Void, rows: Int, deviceId: String?) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        self.deviceId = deviceId
        if let deviceId {
            self.appLoader = DeviceAppsLoader(deviceId: deviceId, dataHandler: RoamDataHandler.shared)
        }
    }

    @State private var appLoader: DeviceAppsLoader?

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth
    @ScaledMetric var gridSpacing: CGFloat = globalGridSpacing
    @ScaledMetric var gridHeightScaled: CGFloat = globalGridHeight

    var appLinks: [AppLink] {
        appLoader?.apps ?? []
    }
    var gridHeight: CGFloat {
        if appLinks.isEmpty {
            return 1
        } else {
            return gridHeightScaled
        }
    }

    @Namespace var linkAnimation

    @MainActor
    init(deviceId: String?, rows: Int, handleOpenApp: @escaping ( AppLink) -> Void) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows
        self.deviceId = deviceId
    }

    var body: some View {
        GeometryReader { geometry in
            if !appLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Spacer()
                    LazyHGrid(rows: Array(repeating:
                                            GridItem(.fixed(CGFloat(gridWidth))), count: rows), spacing: gridSpacing)
                    {
                        ForEach(Array(appLinks.enumerated()), id: \.element.id) { _, app in
                            AppLinkButton(app: app, action: handleOpenApp)
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
            }
        }
            .frame(height: gridHeight * CGFloat(rows))
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                withAnimation(.interpolatingSpring) {
                    // TODO: Update app icons
                }
            }
    }
}

struct AppLinkButton: View {
    let app: AppLink
    let action: ( AppLink) -> Void

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth

    var body: some View {
        Button(action: {
            action(app)
        }, label: {
            VStack {
                FallibleImage(from: app.iconURL, fallback: "questionmark.app.fill", maxSize: gridWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: gridWidth)
                    .shadow(radius: 4)

                Text(app.name)
                #if os(visionOS)
                    .font(.body)
                #else
                    .font(.caption)
                #endif
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .frame(maxWidth: gridWidth)
            }
        })
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview(
    "App Links",
    traits: .fixedLayout(width: 400, height: 300)
) {
    AppLinksView(deviceId: nil, rows: 2, handleOpenApp: { _ in })
        .padding(.bottom, 10)
        .padding(.horizontal, 10)
}
#endif
