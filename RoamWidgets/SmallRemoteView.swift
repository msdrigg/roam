import Foundation
import SwiftUI

struct SmallRemoteView: View {
    let device: DeviceAppEntity?
    let controls: [[RemoteButton?]]

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(0 ..< controls.count, id: \.self) { index in
                let row = controls[index]
                GridRow {
                    ForEach(row.indices, id: \.self) { rowIndex in
                        if let button = row[rowIndex] {
                            if button == .power {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else if [.up, .down, .left, .right, .select].contains(button) {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }.buttonStyle(.borderedProminent)
                            } else {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
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
        .tint(Color.accentColor)
    }
}
