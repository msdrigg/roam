import TipKit
import SwiftUI

struct NoVolumeControlsTip: Tip {
    static let attemptedVolume: Event = Event(id: "attemptedVolumeOnHDMI")

    var title: Text {
        Text("Volume controls unavailable")
    }

    var image: Image? {
        Image(systemName: "speaker.slash")
    }

    var message: Text? {
        Text(
            // swiftlint:disable:next line_length
            "This Roku device can't change its volume from Roam. Roku sticks, Roku Express, and other HDMI-connected players route audio over HDMI, so you'll need to use your TV or receiver remote to adjust volume."
        )
    }

    var rules: [Rule] {
        #Rule(Self.attemptedVolume) {
            $0.donations.count > 0
        }
    }
}
