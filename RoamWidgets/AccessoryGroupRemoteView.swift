import Foundation
import SwiftUI
import WidgetKit

#if os(watchOS)
struct AccessoryGroupRemoteView: View {
    let device: DeviceAppEntity?
    let controls: [RemoteButton?]

    var body: some View {
        if #available(watchOS 11.0, *) {
            AccessoryWidgetGroup(String(localized: "Roku Controls", comment: "Label on a widget for interactions with my application"), systemImage: "tv") {
                ForEach(0 ..< controls.count, id: \.self) { index in
                    if let button = controls[index] {
                        if button == .power {
                            Button(intent: ButtonPressIntent(button, device: device)) {
                                button.label
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        } else if [.up, .down, .left, .right, .select].contains(button) {
                            Button(intent: ButtonPressIntent(button, device: device)) {
                                button.label
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            Button(intent: ButtonPressIntent(button, device: device)) {
                                button.label
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
                .labelStyle(.iconOnly)
            }
            .environment(\.layoutDirection, .leftToRight)
            .fontDesign(.rounded)
            .font(.body.bold())
            .accessoryWidgetGroupStyle(.roundedSquare)
            .tint(Color("AccentColor"))
        }
    }
}
#endif
