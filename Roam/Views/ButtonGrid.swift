import Foundation
import SwiftUI

struct ButtonGrid: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton, _: Bool) -> Void
    let enabled: Set<RemoteButton>
    let disabled: Set<RemoteButton>

    @ScaledMetric var buttonWidth = globalButtonWidth
    @ScaledMetric var buttonHeight = globalButtonHeight
    @ScaledMetric var buttonSpacing = globalButtonSpacing

    @ViewBuilder
    func maybeTipButton(_ button: (String, String, RemoteButton, CustomKeyboardShortcut.Key)) -> some View {
        let view = Button(action: {
            print("Ignoring inner button press")
        }, label: {
            Label(button.0, systemImage: button.1)
                .frame(width: buttonWidth, height: buttonHeight)
        })
        .simultaneousGesture(LongPressGesture().onEnded { _ in
            print("Secret Long Press Action!")
            action(button.2, true)
        })
        .simultaneousGesture(TapGesture().onEnded {
            print("Boring regular tap")
            action(button.2, false)
        })

        if button.2 == .headphonesMode && !disabled.contains(button.2){
            view
            #if os(iOS)
                .popoverTip(HeadphonesModeTip(interfaceIdiom: UIDevice.current.userInterfaceIdiom))
            #elseif !os(watchOS)
                .popoverTip(HeadphonesModeTip())
            #endif
        } else {
            view
        }
    }

    var body: some View {
        let buttonRows: [[(String, String, RemoteButton, CustomKeyboardShortcut.Key)]] = [
            [("Replay", "arrow.uturn.backward", .instantReplay, .instantReplay),
             ("Options", "asterisk", .options, .options),
             ("Headphones mode", "headphones", .headphonesMode, .headphonesMode)],
            [("Rewind", "backward", .rewind, .rewind),
             ("Play/Pause", "playpause", .playPause, .playPause),
             ("Fast Forward", "forward", .fastForward, .fastForward)],
            [("Volume Down", "speaker.minus", .volumeDown, .volumeDown),
             ("Mute", "speaker.slash", .mute, .mute),
             ("Volume Up", "speaker.plus", .volumeUp, .volumeUp)],
        ]
        return Grid(horizontalSpacing: buttonSpacing, verticalSpacing: buttonSpacing) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
                        let view = maybeTipButton(button)
                            .disabled(disabled.contains(button.2))
                            .breatheEffect(enabled.contains(button.2))
                            .symbolEffect(.bounce, value: pressCounter(button.2))
#if os(macOS)
                            .tint(Color.secondary)
                            .buttonStyle(.borderedProminent)
#endif
#if !os(visionOS)
                            .sensoryFeedback(.impact, trigger: pressCounter(button.2))

#endif
                            view
#if !os(tvOS) && !os(watchOS)
                            .customKeyboardShortcut(button.3)
#endif
                    }
                }
            }
        }
        .fixedSize()
    }
}
