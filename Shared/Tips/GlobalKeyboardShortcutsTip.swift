#if os(macOS)
import TipKit
import SwiftUI

struct GlobalKeyboardShortcutTip: Tip {
    var title: Text = Text("Want a keyboard shortcut that works everywhere?")
    var message: Text? = Text("Open the \"Shortcuts\" application, and choose one of the Roam shortcuts. Then add a [keyboard shortcut](https://support.apple.com/guide/shortcuts-mac/launch-a-shortcut-from-another-app-apd163eb9f95/7.0/mac/14.0#apd94a0e7c32) to it")
    
    static let viewedKeyboardShortcuts: Event = Event(id: "viewedKeyboardShortcuts")

    var rules: [Rule] {
        #Rule(Self.viewedKeyboardShortcuts) {
            $0.donations.count <= 3
        }
    }

    var actions: [Action] {
        Action(id: "open-shortcuts", title: "Open shortcuts")
    }
}
#endif
