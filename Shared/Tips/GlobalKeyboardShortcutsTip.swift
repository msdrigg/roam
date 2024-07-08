import TipKit
import SwiftUI

// TODO: Add inline to keyboardshort page
struct GlobalKeyboardShortcutTip: Tip {
    var title: Text = Text("Want to setup a global ")

    var image: Image = Image(systemName: "keyboard")

    // TODO: Make only appear for the first 2 times when opening keyboard shortcuts page (or until dismissed?)
}
