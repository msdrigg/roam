#if os(macOS)
    import AppKit
    import SwiftUI

    struct CaptureVerticalScrollWheelModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(ScrollWheelHandlerView())
        }

        struct ScrollWheelHandlerView: NSViewRepresentable {
            func makeNSView(context _: Context) -> NSView {
                let view = ScrollWheelReceivingView()
                return view
            }

            func updateNSView(_: NSView, context _: Context) {}
        }

        final class ScrollWheelReceivingView: NSView {
            private var scrollVelocity: CGFloat = 0
            private var decelerationTimer: Timer?

            override var acceptsFirstResponder: Bool { true }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
            }

            override func scrollWheel(with event: NSEvent) {
                if event.hasPreciseScrollingDeltas || abs(event.scrollingDeltaX) > 0.000001 || abs(event.deltaX) > 0.000001 {
                    super.scrollWheel(with: event)
                    return
                }

                if let cgEvent = event.cgEvent?.copy() {
                    cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: Double(event.scrollingDeltaY / 10))
                    cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: Double(0))
                    cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis3, value: Double(0))
                    cgEvent.setDoubleValueField(.mouseEventDeltaX, value: Double(0))
                    cgEvent.setDoubleValueField(.mouseEventDeltaY, value: Double(0))

                    if let nsEvent = NSEvent(cgEvent: cgEvent) {
                        super.scrollWheel(with: nsEvent)
                    } else {
                        super.scrollWheel(with: event)
                    }
                } else {
                    super.scrollWheel(with: event)
                }
            }
        }
    }

    extension View {
        func captureVerticalScrollWheel() -> some View {
            modifier(CaptureVerticalScrollWheelModifier())
        }
    }
#endif
