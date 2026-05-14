import SwiftUI
import Foundation

#if os(visionOS)
    let globalButtonWidth: CGFloat = 44
    let globalButtonHeight: CGFloat = 36
    let globalButtonSpacing: CGFloat = 10
    let globalAppLinkShrinkWidth: CGFloat = 500
    let globalButtonHeightPadding: CGFloat = 30
    let globalButtonWidthPadding: CGFloat = 40
    let globalButtonHeightPaddingSmall: CGFloat = 20
    let globalButtonWidthPaddingSmall: CGFloat = 28
    let globalGlowingRadius: CGFloat = 6
    let globalButtonRadius: CGFloat = 10
#elseif os(macOS)
    let globalButtonWidth: CGFloat = 42
    let globalButtonHeight: CGFloat = 34
    let globalButtonSpacing: CGFloat = 8
    let globalButtonHeightPadding: CGFloat = 4
    let globalButtonWidthPadding: CGFloat = 16
    let globalButtonHeightPaddingSmall: CGFloat = 6
    let globalButtonWidthPaddingSmall: CGFloat = 8
    let globalButtonRadius: CGFloat = 7
    let globalGlowingRadius: CGFloat = 4
    let globalAppLinkShrinkWidth: CGFloat = 500
#else
    let globalButtonSpacing: CGFloat = 10
    let globalButtonWidth: CGFloat = 28
    let globalButtonHeight: CGFloat = 20
    let globalButtonPadding: CGFloat = 16
    let globalButtonHeightPadding: CGFloat = 30
    let globalButtonWidthPadding: CGFloat = 40
    let globalAppLinkShrinkWidth = 700
    let globalButtonRadius: CGFloat = 10
    let globalButtonHeightPaddingSmall: CGFloat = 12
    let globalGlowingRadius: CGFloat = 6
    let globalButtonWidthPaddingSmall: CGFloat = 18
#endif

@propertyWrapper
struct AppStorageColor: DynamicProperty {
    private let defaultValue: Color

    @AppStorage var colorData: Data?
    @Environment(\.self) var env

    init(wrappedValue defaultValue: Color, _ key: String) {
        self._colorData  = AppStorage(key)
        self.defaultValue = defaultValue
    }

    var wrappedValue: Color {
        get {
            if let colorData {
                return Color(fromData: colorData) ?? defaultValue
            } else {
                return defaultValue
            }
        }
        nonmutating set {
            let resolved = newValue.resolve(in: env)
            colorData = resolved.toData()
        }
    }

    @MainActor
    var projectedValue: Binding<Color> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

struct CustomAccentColorTint: ViewModifier {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = Color("AccentColor")

    func body(content: Content) -> some View {
        content
            .tint(customAccentColor)
    }
}

struct CustomAccentColorForeground: ViewModifier {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = Color("AccentColor")

    func body(content: Content) -> some View {
        content
            .foregroundStyle(customAccentColor)
    }
}

struct GlassIfSupportedButtonStyle: PrimitiveButtonStyle {
    var isProminent: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        #if os(visionOS)
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonStyle(.bordered)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            if isProminent {
                Button(role: configuration.role, action: configuration.trigger) {
                    configuration.label
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(role: configuration.role, action: configuration.trigger) {
                    configuration.label
                }
                .buttonStyle(.glass)
            }
        } else {
            if isProminent {
                Button(role: configuration.role, action: configuration.trigger) {
                    configuration.label
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(role: configuration.role, action: configuration.trigger) {
                    configuration.label
                }
                .buttonStyle(.bordered)
            }
        }
        #endif
    }
}

extension PrimitiveButtonStyle where Self == GlassIfSupportedButtonStyle {
    static var glassIfSupported: GlassIfSupportedButtonStyle {
        GlassIfSupportedButtonStyle()
    }

    static func glassIfSupported(isProminent: Bool) -> GlassIfSupportedButtonStyle {
        GlassIfSupportedButtonStyle(isProminent: isProminent)
    }
}

struct GlassContainerIfSupported<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if os(visionOS)
        content
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #endif
    }
}

extension View {
    func customAccentColorTint() -> some View {
        modifier(CustomAccentColorTint())
    }

    func customAccentColorForeground() -> some View {
        modifier(CustomAccentColorForeground())
    }

    @ViewBuilder
    func glassEffectIfSupported() -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            self.glassEffect()
        } else {
            self
        }
        #endif
    }

    @ViewBuilder
    func glassEffectIfSupported<S: Shape>(
        tint: Color? = nil,
        isInteractive: Bool = true,
        in shape: S
    ) -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            self.glassEffect(
                .regular
                    .tint(tint)
                    .interactive(isInteractive),
                in: shape
            )
        } else {
            self
        }
        #endif
    }

    func glassEffectIfSupported(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        isInteractive: Bool = true
    ) -> some View {
        glassEffectIfSupported(
            tint: tint,
            isInteractive: isInteractive,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func liquidGlass(
        isProminent: Bool = false,
        isInteractive: Bool = true,
        cornerRadius: CGFloat = globalButtonRadius
    ) -> some View {
        #if os(macOS)
        let tint: Color? = nil
        #else
        let tint = isProminent ? Color.accentColor.opacity(0.18) : nil
        #endif

        return glassEffectIfSupported(
            cornerRadius: cornerRadius,
            tint: tint,
            isInteractive: isInteractive
        )
    }

    @ViewBuilder
    func glassContainerIfSupported(spacing: CGFloat? = nil) -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
        #endif
    }
}

extension Color.Resolved {
    func toData() -> Data? {
        let colorData = ColorData(red: red, green: green, blue: blue, opacity: opacity)
        let encoder = PropertyListEncoder()
        return try? encoder.encode(colorData)
    }

    init?(fromData data: Data) {
        let decoder = PropertyListDecoder()
        guard let colorData = try? decoder.decode(ColorData.self, from: data) else {
            return nil
        }

        self.init(red: colorData.red, green: colorData.green, blue: colorData.blue, opacity: colorData.opacity)
    }
}

extension Color {
    init?(fromData data: Data) {
        guard let resolved = Color.Resolved(fromData: data) else { return nil }
        self = Color(cgColor: resolved.cgColor)
    }
}

// Helper struct for encoding/decoding
private struct ColorData: Codable {
    let red: Float
    let green: Float
    let blue: Float
    let opacity: Float
}

extension UserDefaults {
    func setColor(_ color: Color.Resolved, forKey key: String) {
        self.setValue(color.toData(), forKey: key)
    }

    func color(forKey key: String) -> Color? {
        guard let data = data(forKey: key) else { return nil }
        guard let resolved = Color.Resolved(fromData: data) else { return nil }
        return Color(cgColor: resolved.cgColor)
    }
}

extension View {
    func applyBuilder<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }

    func removeToolbarTitle() -> some View {
        self.applyBuilder {
            #if !os(watchOS)
            if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
                $0
                    .toolbar(removing: .title)
            } else {
                $0
            }
            #else
            $0
            #endif
        }
    }

    func removeToolbarBackground() -> some View {
        self.applyBuilder {
#if !os(iOS) && !os(watchOS) && !os(visionOS)
            if #available(macOS 15.0, *) {
                $0
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            } else {
                $0
            }
            #else
            $0
            #endif
        }
    }

    func translucentBackground() -> some View {
        self.applyBuilder {
            #if !os(iOS) && !os(watchOS) && !os(visionOS)
            if #available(macOS 15.0, *) {
                $0.containerBackground(.thickMaterial, for: .window)
            } else {
                $0
            }
            #else
            $0
            #endif
        }
    }

    func enableResize() -> some View {
        self.applyBuilder {
            #if !os(iOS) && !os(watchOS) && !os(visionOS)
            if #available(macOS 15.0, *) {
                $0.windowResizeBehavior(.enabled)
            } else {
                $0
            }
#else
$0
#endif
        }
    }
    func disableWindowMinimize() -> some View {
        self.applyBuilder {
#if !os(iOS) && !os(watchOS) && !os(visionOS)
            if #available(macOS 15.0, *) {
                $0.windowMinimizeBehavior(.disabled)
            } else {
                $0
            }
            #else
            $0
            #endif
        }
    }

    func breatheEffect(_ enabled: Bool) -> some View {
        self.modifier(BreatheEffect(enabled: enabled))
    }
}

struct BreatheEffect: ViewModifier {
    @ScaledMetric var buttonWidth = (globalButtonWidth + globalButtonWidthPadding)
    @ScaledMetric var buttonHeight = (globalButtonHeight + globalButtonHeightPadding)
    @ScaledMetric var buttonRadius = globalButtonRadius
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            ZStack {
                // Outer circle
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(customAccentColor)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .opacity(0.2)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .scaleEffect(phase ? 1 : 1.1)
                    } animation: { _ in
                            .easeOut(duration: 1)
                    }

                // Middle circle
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(customAccentColor)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .opacity(0.5)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .scaleEffect(phase ? 1 : 1.2)
                    } animation: { _ in
                            .easeIn(duration: 1)
                    }

                // Inner circle
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(customAccentColor)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .opacity(0.3)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .scaleEffect(phase ? 1 : 1.3)
                    } animation: { _ in
                            .easeInOut(duration: 1)
                    }

                content
                    .tint(customAccentColor)
                    .buttonStyle(.glassIfSupported)
            }
            .frame(width: buttonWidth, height: buttonHeight)
        } else {
            content
        }
    }
}

extension Scene {
    func disableRestoration() -> some Scene {
#if !os(iOS) && !os(watchOS) && !os(visionOS)
        return self.restorationBehavior(.disabled)
#else
        return self
#endif
    }
    func enableBackgroundDragging() -> some Scene {
#if os(macOS)
        if #available(macOS 15.0, *) {
            return self.windowBackgroundDragBehavior(.enabled)
        } else {
            return self
        }
#else
        return self
#endif
    }

    func trailingPosition() -> some Scene {
        #if os(macOS)
        return self.defaultPosition(.trailing)
        #else
        return self
        #endif
    }
}

struct ContentView: View {
    @State private var isPinging = true

    var body: some View {
        VStack {
            Button(action: {
                isPinging.toggle()
            }, label: {
                Text("Press Me")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            })
            .breatheEffect(isPinging)
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
