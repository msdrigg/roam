import Foundation
import SwiftUI

struct SmallRemoteView: View {
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var customAccentColor: Color = .accentColor

    let device: Device?
    let controls: [[RemoteButton?]]

    private static let dpadButtons: Set<RemoteButton> = [.up, .down, .left, .right, .select]

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
            Button(intent: ButtonPressIntent(button, device: device)) {
                buttonLabel(button)
            }
            .buttonStyle(.borderedProminent)
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
