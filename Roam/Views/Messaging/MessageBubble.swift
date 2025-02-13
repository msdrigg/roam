import SwiftUI

struct MessageBubble: View {
    let message: Message

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            if message.author == .me {
                Spacer()
                MessageViewText(message)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.accentColor.opacity(0.5))
                    .foregroundStyle(
                        colorScheme == .dark ? Color.white : Color.black
                    )
                    .cornerRadius(15)
                    .padding(.trailing, 10)
            } else {
                MessageViewText(message)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.5))
                    .cornerRadius(15)
                    .padding(.leading, 10)
                Spacer()
            }
        }
    }
}

// swiftlint:disable:next force_try
@MainActor private let linkDetector = try! Regex(#"https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)"#)

private struct LinkedText: View {
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

private struct MessageViewText: View {
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
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("Messaging Bubble") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi Scott, this is a test message",
        author: .me
    ))
        .padding()
}

#Preview("Messaging Bubble Response") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi dude, this is a response message with a https://example.com link",
        author: .support
    ))
        .padding()
}

#Preview("Messaging Bubble Response Robot") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi dude, this is a response message [https://test.com]",
        author: .support,
        robotMessage: true
    ))
        .padding()
}
#endif
