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

struct MessageViewText: View {
    let message: Message

    init(_ message: Message) {
        self.message = message
    }

    var alignment: HorizontalAlignment {
        if message.author == .support {
            return .leading
        } else if message.author == .me {
            return .trailing
        } else {
            return .trailing
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            if let title = message.messageTitle {
                Text(title)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .font(.caption)
            }
            LinkedText(message.message)
            if message.robotMessage {
                Text("P.S. This is an auto-reply. 🤖")
            }
        }
    }
}
