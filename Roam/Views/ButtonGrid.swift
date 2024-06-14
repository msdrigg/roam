import Foundation
import SwiftUI

struct ButtonGrid: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let enabled: Set<RemoteButton>
    let disabled: Set<RemoteButton>

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
        return Grid(horizontalSpacing: globalButtonSpacing, verticalSpacing: globalButtonSpacing) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
                        let view = Button(action: { action(button.2) }, label: {
                            Label(button.0, systemImage: button.1)
                                .frame(width: globalButtonWidth, height: globalButtonHeight)
                        })
                        #if os(macOS)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.secondary)
                        #endif
                        .disabled(disabled.contains(button.2))
                        .breatheEffect(enabled.contains(button.2))
                        .symbolEffect(.bounce, value: pressCounter(button.2))
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
    }
}
