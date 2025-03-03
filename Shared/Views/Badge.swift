import SwiftUI

struct BadgeLabelStyle: LabelStyle {
    var color: Color = .blue
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = 10.0

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
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        #endif
        .truncationMode(.tail)
        .lineLimit(1)
        .background(color)
        .clipShape(Capsule())
        .foregroundColor(color.isLightColor ? .black : .white)
        .font(.caption2)
    }
}

extension LabelStyle where Self == BadgeLabelStyle {
    static func badge(_ color: Color) -> BadgeLabelStyle {
        BadgeLabelStyle(color: color)
    }
}

#if canImport(UIKit)
    extension Color {
        var isLightColor: Bool {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)

            let brightness = (red * 299 + green * 587 + blue * 114) / 1000
            return brightness > 0.5
        }
    }
#else
    extension Color {
        var isLightColor: Bool {
            guard let rgbColor = NSColor(self).usingColorSpace(.deviceRGB) else {
                return false
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            rgbColor.getRed(&red, green: &green, blue: &blue, alpha: nil)

            let brightness = (red * 299 + green * 587 + blue * 114) / 1000
            return brightness > 0.5
        }
    }
#endif

#if DEBUG
#Preview(
    "About",
    traits: .fixedLayout(width: 200.0, height: 300.0)
) {
    Label(String("Test Badge!"), systemImage: "keyboard")
        .padding()
        .labelStyle(.badge(Color.green))
        .modelContainer(previewContainer)
}
#endif
