import Foundation
import SwiftUI
import WidgetKit

struct SmallRemoteView: View {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor
    @Environment(\.widgetRenderingMode) private var renderingMode

    let device: Device?
    let controls: [[RemoteButton?]]

    private static let dpadButtons: Set<RemoteButton> = [.up, .down, .left, .right, .select]

    /// Tinted and clear home screens (`.accented`) and the lock screen (`.vibrant`) redraw the
    /// widget from the luminance of whatever we hand them, so a prominent button's filled
    /// background flattens into an opaque block and swallows the glyph sitting on top of it —
    /// the dpad turns into five blank squares. Only fill the dpad when we are drawing our own
    /// colors, and let `widgetAccentable` carry the emphasis everywhere else.
    private var drawsOwnColors: Bool {
        renderingMode == .fullColor
    }

    private func buttonLabel(_ button: RemoteButton) -> some View {
        button.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func remoteButton(_ button: RemoteButton) -> some View {
        if button == .power {
            Button(intent: ButtonPressIntent(button, device: device)) {
                buttonLabel(button).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        } else if Self.dpadButtons.contains(button) {
            let dpadButton = Button(intent: ButtonPressIntent(button, device: device)) {
                buttonLabel(button)
            }
            if drawsOwnColors {
                dpadButton.buttonStyle(.borderedProminent)
            } else {
                dpadButton.buttonStyle(.bordered).widgetAccentable()
            }
        } else {
            Button(intent: ButtonPressIntent(button, device: device)) {
                buttonLabel(button)
            }
        }
    }

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(0 ..< controls.count, id: \.self) { index in
                let row = controls[index]
                GridRow {
                    ForEach(row.indices, id: \.self) { rowIndex in
                        if let button = row[rowIndex] {
                            remoteButton(button)
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .fontDesign(.rounded)
        .font(.body.bold())
        .buttonBorderShape(.roundedRectangle)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .tint(customAccentColor)
    }
}
