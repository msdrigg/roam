import TipKit
import SwiftUI

struct HeadphonesModeTip: Tip {
    static let toggledHeadphonesMode: Event = Event(id: "toggledHeadphonesMode")
    static let toggledMuteOrPlayPause: Event = Event(id: "toggledMuteOrPlayPause")

    #if os(iOS)
    var interfaceIdiom: UIUserInterfaceIdiom = .phone
    #endif
    var title: Text = Text("Want to listen through your device?")
    var image: Image? {
        Image(systemName: "headphones")
    }

    #if os(iOS)
    init(interfaceIdiom: UIUserInterfaceIdiom, title: Text = Text("Want to listen through your device?")) {
        self.interfaceIdiom = interfaceIdiom
        self.title = title
    }
    #else
    init(title: Text = Text("Want to listen through your device?")) {
        self.title = title
    }
    #endif

    var message: Text? {
        #if os(macOS)
        Text("Click here to play your TV audio through your computer!")
        #elseif os(visionOS)
        Text("Click here to play your TV audio through your Vision Pro!")
        #else
        if interfaceIdiom == .pad {
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
