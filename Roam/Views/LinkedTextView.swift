import SwiftUI

// swiftlint:disable:next force_try
@MainActor private let linkDetector = try! Regex(#"https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)"#)

struct LinkedText: View {
    let text: String
    let replaced: String

    init (_ text: String) {
        self.text = text

        // find the ranges of the string that have URLs
        replaced = text.replacing(linkDetector, with: { match in "[\(text[match.range])](\(text[match.range]))" })
    }

    var body: Text {
        Text(.init(replaced))
    }
}
