import SwiftUI
import TipKit

struct GlowingModifier: ViewModifier {
    @State private var animate = false

    @ScaledMetric var buttonRadius = globalButtonRadius
    @ScaledMetric var glowRadius = globalGlowingRadius

    let gradientColors = Gradient(colors: [.teal, .blue, .pink, .purple, .indigo])

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(Material.ultraThick)
#if os(macOS)
                    .overlay(
                        HoverEffectBackground()
                            .cornerRadius(buttonRadius)
                   )
#endif
            )
            .padding(glowRadius)
            .background(
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(AngularGradient(gradient: gradientColors, center: .center, angle: .degrees(animate ? 360 : 0)))
                    .blur(radius: glowRadius)
            )
            .padding(glowRadius * 2 - glowRadius / 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}

struct PaddedBorderlessButtonStyleWithChevron: ButtonStyle {
    @ScaledMetric var buttonPaddingWidth = globalButtonWidthPaddingSmall
    @ScaledMetric var buttonPaddingHeight = globalButtonHeightPaddingSmall
    @ScaledMetric var buttonRadius = globalButtonRadius

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.label

            Label("Down", systemImage: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.caption.bold())
        }
        .padding(.horizontal, buttonPaddingWidth)
        .padding(.vertical, buttonPaddingHeight)
        .contentShape(.rect(cornerRadius: buttonRadius))
    }
}
struct PaddedBorderlessButtonStyle: ButtonStyle {
    @ScaledMetric var buttonPaddingWidth = globalButtonWidthPaddingSmall
    @ScaledMetric var buttonPaddingHeight = globalButtonHeightPaddingSmall
    @ScaledMetric var buttonRadius = globalButtonRadius

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        .padding(.horizontal, buttonPaddingWidth)
        .padding(.vertical, buttonPaddingHeight)
        .contentShape(.rect(cornerRadius: buttonRadius))
    }
}

extension View {
    func glowing(enabled: Bool = true) -> some View {
        if enabled {
            AnyView(self.modifier(GlowingModifier()))
        } else {
            AnyView(self)
        }
    }
}

#Preview("GlowingBorderedButton") {
    Button(action: {
        print("Button Pressed")
    }, label: {
        Text("Glowing")
    })
    .buttonStyle(.bordered)
    .controlSize(.large)
    .glowing()
    .padding(100)
}

#Preview("GlowingBorderlessButton") {
    Button(action: {
        print("Button Pressed")
    }, label: {
        Text("Glowing")
    })
    .buttonStyle(PaddedBorderlessButtonStyle())
    .glowing()
}
