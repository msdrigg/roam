#if os(macOS)
    import SwiftUI

    struct PaddedHoverButtonStyle: ButtonStyle {
        var padding: EdgeInsets

        func makeBody(configuration: Self.Configuration) -> some View {
            configuration.label
                .padding(padding)
                .background(HoverOrClickedEffectBackground(configuration: configuration))
                .cornerRadius(5) // Mimic accessoryBar style corner radius
        }

        struct HoverOrClickedEffectBackground: View {
            @State private var isHovered = false
            let configuration: ButtonStyle.Configuration

            var body: some View {
                Rectangle()
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.4) : isHovered ? Color.secondary
                        .opacity(0.2) : Color.clear)
                    .preciseHovered { hover in
                        isHovered = hover
                    }
                    .animation(.easeInOut, value: isHovered || configuration.isPressed)
            }
        }
    }

    public struct HoverEffectBackground: View {
        @State private var isHovered = false

        @ScaledMetric private var buttonRadius = globalButtonRadius

        public var body: some View {
            Rectangle()
                .fill(isHovered ? Color.secondary
                    .opacity(0.2) : Color.clear)
                .preciseHovered { hover in
                    isHovered = hover
                }
                .animation(.easeInOut.speed(2), value: isHovered)
                .cornerRadius(buttonRadius)
        }
    }

    extension View {
        func hoverHighlight(enabled: Bool = true) -> some View {
            if enabled {
                return AnyView(
                    self
                    #if os(macOS)
                        .background(
                            HoverEffectBackground()
                       )
                    #else
                        .hoverEffect(.highlight)
                    #endif
                )
            } else {
                return AnyView(self)
            }
        }
    }
#endif
