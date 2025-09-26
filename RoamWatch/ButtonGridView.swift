import Foundation
import os.log
import SwiftUI

struct ButtonGridView: View {
    let device: Device?
    let controls: [[RemoteButton?]]

    @Environment(\.layoutDirection) var layoutDirection

    @State var buttonPresses: [RemoteButton: Int] = [:]
    func buttonPressCount(_ key: RemoteButton) -> Int {
        buttonPresses[key] ?? 0
    }

    func incrementButtonPressCount(_ key: RemoteButton) {
        buttonPresses[key] = (buttonPresses[key] ?? 0) + 1
    }

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(controls, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { button in
                        if let button {
                            if button == .power {
                                Button(action: {
                                    incrementButtonPressCount(button)
                                    Task {
                                        do {
                                            try await clickButton(button: button, device: device)
                                        } catch {
                                            Log.userInteraction.error(
                                                "Error pressing button \(String(describing: button), privacy: .public): \(error, privacy: .public)"
                                            )
                                        }
                                    }
                                }, label: {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(.red)
                                        .environment(\.layoutDirection, layoutDirection)
                                })
                                .buttonStyle(.plain)
                                .sensoryFeedback(.impact, trigger: buttonPressCount(button))
                                .symbolEffect(.bounce, value: buttonPressCount(button))
                            } else if [.up, .down, .left, .right, .select].contains(button) {
                                Button(action: {
                                    incrementButtonPressCount(button)
                                    Task {
                                        try? await clickButton(button: button, device: device)
                                    }
                                }, label: {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }).buttonStyle(.borderedProminent)
                                    .sensoryFeedback(.impact, trigger: buttonPressCount(button))
                                    .symbolEffect(.bounce, value: buttonPressCount(button))
                            } else {
                                Button(action: {
                                    incrementButtonPressCount(button)
                                    Task {
                                        try? await clickButton(button: button, device: device)
                                    }
                                }, label: {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                })
                                .sensoryFeedback(.impact, trigger: buttonPressCount(button))
                                .symbolEffect(.bounce, value: buttonPressCount(button))
                            }
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .font(.body.bold())
        .buttonBorderShape(.roundedRectangle)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .environment(\.layoutDirection, .leftToRight)
        .customAccentColorTint()
    }
}
