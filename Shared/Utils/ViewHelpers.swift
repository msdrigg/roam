import SwiftUI

extension View {
    func applyBuilder<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }

    func removeToolbarTitle() -> some View {
        self.applyBuilder {
            #if !os(watchOS)
            if #available(macOS 15.0, iOS 18.0, *) {
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
#if !os(iOS) && !os(watchOS)
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
            #if !os(iOS) && !os(watchOS)
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
            #if !os(iOS) && !os(watchOS)
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
#if !os(iOS) && !os(watchOS)
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
        self.applyBuilder {
            if #available(macOS 15.0, iOS 18.0, watchOS 11.0, *)  {
                $0.symbolEffect(.breathe, isActive: enabled)
            } else {
                $0.symbolEffect(.pulse, isActive: enabled)
            }
        }
    }
}

extension Scene {
    func disableRestoration() -> some Scene {
#if !os(iOS) && !os(watchOS)
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
