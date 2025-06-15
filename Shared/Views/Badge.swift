import SwiftUI

struct BadgeLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = 10.0
    var color: Color = .blue

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: iconWidth) {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
        #if os(visionOS)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        #else
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        #endif
        .truncationMode(.tail)
        .lineLimit(1)
        .background(color.opacity(0.6))
        .clipShape(Capsule())
        .font(.caption2)
    }
}

extension LabelStyle where Self == BadgeLabelStyle {
    static func badge(_ color: Color) -> BadgeLabelStyle {
        BadgeLabelStyle(color: color)
    }
}

#if DEBUG
#Preview(
    "About",
    traits: .fixedLayout(width: 200.0, height: 300.0)
) {
    Label(String("Test Badge!"), systemImage: "keyboard")
        .padding()
        .labelStyle(.badge(Color.green))
}
#endif
