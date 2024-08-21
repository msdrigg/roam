import TipKit
import SwiftUI

struct HeadphonesModeTip: Tip {
    static let toggledHeadphonesMode: Event = Event(id: "toggledHeadphonesMode")
    static let toggledMuteOrPlayPause: Event = Event(id: "toggledMuteOrPlayPause")

    var title: Text = Text("Want to listen through your device?")
    var image: Image? {
        Image(systemName: "headphones")
    }

    var message: Text? {
        #if os(macOS)
        Text("Click here to play your TV audio through your computer!")
        #elseif os(visionOS)
        Text("Click here to play your TV audio through your Vision Pro!")
        #elseif os(tvOS)
        Text("Click here to play your TV audio through your Apple TV!")
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            Text("Click here to play your TV audio through your iPad or connected headphones")
        } else {
            Text("Click here to play your TV audio through your iPhone or connected headphones")
        }
        #endif
    }

    var rules: [Rule] {
        #Rule(Self.toggledHeadphonesMode) {
            $0.donations.count == 0
        }
        #Rule(Self.toggledMuteOrPlayPause) {
            $0.donations.count > 2
        }
    }
}
