import TipKit
import SwiftUI

// TODO: Add popover to headphones mode button
struct HeadphonesModeTip: Tip {
    var title: Text = Text("Want to listen through your headphones?")

    // TODO: Make this say computer/ipad/iphone
    var message: Text = Text("Click here to play your TV audio through your device!")

    var image: Image = Image(systemName: "headphones")

    // TODO: Make only appear after a device has been sucessfully muted/unmuted or play/paused
}
