import SwiftUI

#if os(visionOS)
    let globalButtonWidth: CGFloat = 44
    let globalButtonHeight: CGFloat = 36
    let globalButtonSpacing: CGFloat = 10
    let globalAppLinkShrinkWidth: CGFloat = 500
    let globalButtonHeightPadding: CGFloat = 30
    let globalButtonWidthPadding: CGFloat = 40
    let globalButtonHeightPaddingSmall: CGFloat = 20
    let globalButtonWidthPaddingSmall: CGFloat = 28
    let globalButtonRadius: CGFloat = 10
#elseif os(macOS)
    let globalButtonWidth: CGFloat = 44
    let globalButtonHeight: CGFloat = 36
    let globalButtonSpacing: CGFloat = 10
    let globalButtonHeightPadding: CGFloat = 4
    let globalButtonWidthPadding: CGFloat = 16
    let globalButtonHeightPaddingSmall: CGFloat = 6
    let globalButtonWidthPaddingSmall: CGFloat = 8
    let globalButtonRadius: CGFloat = 6
    let globalAppLinkShrinkWidth: CGFloat = 500
#elseif os(tvOS)
    let globalButtonWidth: CGFloat = 60
    let globalButtonSpacing: CGFloat = 30
    let globalButtonHeight: CGFloat = 50
    let globalButtonPadding: CGFloat = 16
    let globalAppLinkShrinkWidth: CGFloat = 600
    let globalButtonRadius: CGFloat = 10
    let globalButtonHeightPadding: CGFloat = 32
    let globalButtonWidthPadding: CGFloat = 36
    let globalButtonHeightPaddingSmall: CGFloat = 20
    let globalButtonWidthPaddingSmall: CGFloat = 28
#else
    let globalButtonSpacing: CGFloat = 10
    let globalButtonWidth: CGFloat = 28
    let globalButtonHeight: CGFloat = 20
    let globalButtonPadding: CGFloat = 16
    let globalButtonHeightPadding: CGFloat = 30
    let globalButtonWidthPadding: CGFloat = 40
    let globalAppLinkShrinkWidth = 700
    let globalButtonRadius: CGFloat = 10
    let globalButtonHeightPaddingSmall: CGFloat = 16
    let globalButtonWidthPaddingSmall: CGFloat = 24
#endif

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
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            ZStack {
                // Outer circle
                RoundedRectangle(cornerRadius: buttonRadius)
                    .fill(Color("AccentColor"))
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
                    .fill(Color("AccentColor"))
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
                    .fill(Color("AccentColor"))
                    .frame(width: buttonWidth, height: buttonHeight)
                    .opacity(0.3)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .scaleEffect(phase ? 1 : 1.3)
                    } animation: { _ in
                            .easeInOut(duration: 1)
                    }

                content
                    .tint(Color("AccentColor"))
                    .buttonStyle(.borderedProminent)
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
        if #available(macOS 15.0, watchOS 11.0, *) {
            return self.restorationBehavior(.disabled)
        } else {
            return self
        }
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
