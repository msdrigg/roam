import SwiftData
import SwiftUI

#if os(tvOS) || os(visionOS)
    let globalGridWidth: CGFloat = 100
    let globalGridSpacing: CGFloat = 20
    let globalGridHeight: CGFloat = 130
#elseif os(visionOS)
    let globalGridWidth: CGFloat = 80
    let globalGridSpacing: CGFloat = 20
    let globalGridHeight: CGFloat = 130
#else
    let globalGridWidth: CGFloat = 60
    let globalGridSpacing: CGFloat = 10
    let globalGridHeight: CGFloat = 80
#endif

struct AppLinksView: View {
    var handleOpenApp: (AppLinkAppEntity) -> Void
    @Query private var appLinks: [AppLink]
    let rows: Int
    @State var cachedAppLinks: [AppLink]

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth
    @ScaledMetric var gridSpacing: CGFloat = globalGridSpacing
    @ScaledMetric var gridHeightScaled: CGFloat = globalGridHeight

    var gridHeight: CGFloat {
        if cachedAppLinks.isEmpty {
            return 1
        } else {
            return gridHeightScaled
        }
    }

    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String> = Set()
        for appLink in appLinks {
            appLinkPairs.insert("\(appLink.id);\(appLink.icon != nil)")
        }

        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }

    @Namespace var linkAnimation

    @MainActor
    init(deviceId: String?, rows: Int, handleOpenApp: @escaping (AppLinkAppEntity) -> Void) {
        self.handleOpenApp = handleOpenApp
        self.rows = rows

        _appLinks = Query(
            filter: #Predicate {
                $0.deviceUid == deviceId
            },
            sort: [
                SortDescriptor<AppLink>(\.lastSelected, order: .reverse),
                SortDescriptor<AppLink>(\.deviceSortOrder, order: .forward),
                SortDescriptor<AppLink>(\.id)
            ]
        )
        cachedAppLinks = []
    }

    var body: some View {
        GeometryReader { geometry in
            if !cachedAppLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Spacer()
                    LazyHGrid(rows: Array(repeating:
                                            GridItem(.fixed(CGFloat(gridWidth))), count: rows), spacing: gridSpacing)
                    {
                        ForEach(Array(cachedAppLinks.enumerated()), id: \.element.id) { _, app in
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
                cachedAppLinks = appLinks
            }
            .onChange(of: appIdsIconsHashed) {
                withAnimation(.interpolatingSpring) {
                    cachedAppLinks = appLinks
                }
            }
    }
}

struct AppLinkButton: View {
    let app: AppLink
    let action: (AppLinkAppEntity) -> Void

    @ScaledMetric var gridWidth: CGFloat = globalGridWidth
    @ScaledMetric var gridHeight: CGFloat = globalGridHeight

    var body: some View {
        Button(action: {
            action(app.toAppEntity())
        }, label: {
            VStack {
                DataImage(from: app.icon, fallback: "questionmark.app")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: gridWidth)
                    .shadow(radius: 4)

                Text(app.name)
                #if os(tvOS) || os(visionOS)
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
    traits: .fixedLayout(width: 100, height: 300)
) {
    AppLinksView(deviceId: nil, rows: 1, handleOpenApp: { _ in })
        .modelContainer(previewContainer)
}

#Preview(
    traits: .fixedLayout(width: 100, height: 300)
) {
    AppLinksView(deviceId: nil, rows: 2, handleOpenApp: { _ in })
        .modelContainer(previewContainer)
}
#endif
