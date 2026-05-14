import Foundation
import SwiftUI

struct ButtonGrid: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let enabled: Set<RemoteButton>
    let disabled: Set<RemoteButton>
    var usesNativeGlassButtons = false
    var noVolumeControls = false
    var headphonesModeUnsupported = false

    @ScaledMetric var buttonWidth = globalButtonWidth
    @ScaledMetric var buttonHeight = globalButtonHeight
    @ScaledMetric var buttonSpacing = globalButtonSpacing

#if !os(watchOS)
    @State private var showHeadphonesTip = false
    @State private var showHeadphonesUnsupportedTip = false
    @State private var pendingVolumeTipButton: RemoteButton?
    @AppStorage(UserDefaultKeys.headphonesModeUsed) private var headphonesModeUsed: Bool = false
    @AppStorage(UserDefaultKeys.audioInteractionCount) private var audioInteractionCount: Int = 0
#endif

    private static let volumeButtons: Set<RemoteButton> = [.volumeUp, .volumeDown, .mute]

    private func isVolumeButtonNoOp(_ button: RemoteButton) -> Bool {
        noVolumeControls && Self.volumeButtons.contains(button)
    }

#if !os(watchOS)
    private func volumeTipBinding(for button: RemoteButton) -> Binding<Bool> {
        Binding(
            get: { pendingVolumeTipButton == button },
            set: { newValue in
                if !newValue, pendingVolumeTipButton == button {
                    pendingVolumeTipButton = nil
                }
            }
        )
    }
#endif

    @ViewBuilder
    func maybeTipButton(_ button: (String, String, RemoteButton, CustomKeyboardShortcut.Key)) -> some View {
        let isVolumeNoOp = isVolumeButtonNoOp(button.2)
        let isHeadphonesNoOp = headphonesModeUnsupported && button.2 == .headphonesMode
        let appearsDisabled = isVolumeNoOp || isHeadphonesNoOp
        let view = Button(action: {
            #if !os(watchOS)
            if button.2 == .headphonesMode {
                if isHeadphonesNoOp {
                    showHeadphonesUnsupportedTip = true
                    return
                }
                headphonesModeUsed = true
                showHeadphonesTip = false
                HeadphonesModeTip.toggledHeadphonesMode.sendDonation()
            }
            if button.2 == .mute || button.2 == .playPause {
                HeadphonesModeTip.toggledMuteOrPlayPause.sendDonation()
                if !isVolumeNoOp && !headphonesModeUnsupported {
                    audioInteractionCount += 1
                    if !headphonesModeUsed && audioInteractionCount > 2 {
                        showHeadphonesTip = true
                    }
                }
            }
            if isVolumeNoOp {
                NoVolumeControlsTip.attemptedVolume.sendDonation()
                pendingVolumeTipButton = button.2
                return
            }
            #endif
            action(button.2)
        }, label: {
            Label(button.0, systemImage: button.1)
                .frame(width: buttonWidth, height: buttonHeight)
                .foregroundStyle(appearsDisabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .opacity(appearsDisabled ? 0.55 : 1.0)
        })

#if !os(watchOS)
        if button.2 == .headphonesMode && isHeadphonesNoOp {
            view.popover(isPresented: $showHeadphonesUnsupportedTip) {
                HeadphonesUnsupportedTipContent()
            }
        } else if button.2 == .headphonesMode && !disabled.contains(button.2) {
            view.popover(isPresented: $showHeadphonesTip) {
                HeadphonesModeTipContent()
            }
        } else if isVolumeNoOp {
            view.popover(isPresented: volumeTipBinding(for: button.2)) {
                NoVolumeControlsTipContent()
            }
        } else {
            view
        }
#else
        view
#endif
    }

    @Environment(\.colorScheme) var colorScheme

    #if os(macOS)
    var macTintColor: Color {
        if colorScheme == .dark {
            return Color.secondary
        } else {
            return Color.white
        }
    }
    #endif

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
#if !os(visionOS)
                            .sensoryFeedback(.impact, trigger: pressCounter(button.2))

#endif
                            view
#if !os(watchOS)
                            .customKeyboardShortcut(button.3)
#endif
                    }
                }
            }
        }
        .fixedSize()
    }
}

#if !os(watchOS)
private struct HeadphonesModeTipContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(
                    localized: "Want to listen through your device?",
                    comment: "Headphones mode promo title"
                ),
                systemImage: "headphones"
            )
            .font(.headline)

            promoBody
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private var promoBody: some View {
        #if os(macOS)
        Text(
            "Click here to play your TV audio through your computer!",
            comment: "Headphones mode promo body (macOS)"
        )
        #elseif os(visionOS)
        Text(
            "Click here to play your TV audio through your Vision Pro!",
            comment: "Headphones mode promo body (visionOS)"
        )
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            Text(
                "Click here to play your TV audio through your iPad or connected headphones",
                comment: "Headphones mode promo body (iPad)"
            )
        } else {
            Text(
                "Click here to play your TV audio through your iPhone or connected headphones",
                comment: "Headphones mode promo body (iPhone)"
            )
        }
        #endif
    }
}

private struct HeadphonesUnsupportedTipContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(
                    localized: "Headphones mode unavailable",
                    comment: "Title of the popup shown when a user taps a disabled headphones mode button"
                ),
                systemImage: "headphones"
            )
            .font(.headline)

            Text(
                "This Roku device doesn't support streaming audio to Roam, so headphones mode is unavailable. To see which Roku devices do support it, visit https://www.roku.com/products/compare.",
                comment: "Body of the popup shown when a user taps a disabled headphones mode button"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }
}

private struct NoVolumeControlsTipContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(
                    localized: "Volume controls unavailable",
                    comment: "Title of the popup shown when a user taps a disabled volume button"
                ),
                systemImage: "speaker.slash"
            )
            .font(.headline)

            Text(
                // swiftlint:disable:next line_length
                "This Roku device can't change its volume from Roam. Roku sticks, Roku Express, and other HDMI-connected players route audio over HDMI, so you'll need to use your TV or receiver remote to adjust volume.",
                comment: "Body of the popup shown when a user taps a disabled volume button"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }
}
#endif
