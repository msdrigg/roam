import SwiftUI

struct MessageBubble: View {
    let message: Message
    let previous: Message?

    @Environment(\.colorScheme) var colorScheme
    
    var shownWeekday: String? {
        if message.robotMessage || message.id == "start" {
            return nil
        }
        
        guard let currentDate = parseDiscordSnowflake(message.id) else {
            return nil
        }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE" // Full weekday name
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        let weekday = formatter.string(from: currentDate)

        guard let previous, let previousDate = parseDiscordSnowflake(previous.id) else {
            return weekday
        }
        let previousComponents = calendar.dateComponents([.year, .month, .day], from: previousDate)

        if currentComponents != previousComponents {
            return weekday
        }

        return nil
    }

    var color: Color {
        if message.author == .me {
            Color.me
        } else {
            Color.support
        }
    }

    var foregroundColor: Color {
        return colorScheme == .dark ? Color.white : Color.black
    }

    var body: some View {
        VStack(spacing: 4) {
            if let shownWeekday {
                HStack {
                    Spacer()
                    Text(shownWeekday)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
            if !message.message.isEmpty {
                MessageFraming(message: message) {
                    MessageViewText(message)
                        .background(color)
                        .overlay(alignment: .bottomTrailing) {
                            MessageMetadataOverlay(message: message)
                                .foregroundStyle(Color.secondary)
                        }
#if !os(watchOS)
#if !os(macOS)
                        .contentShape([.contextMenuPreview], RoundedRectangle(cornerRadius: 15))
#endif
                        .contextMenu {
                            Button(action: {
                                let copying = [message.messageTitle, message.message].compactMap{$0}.joined(separator: "\n")
                                
#if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(copying, forType: .string)
#else
                                UIPasteboard.general.string = copying
#endif
                            }, label: {
                                Label(String(localized: "Copy", comment: "Label on a button to copy the text"), systemImage: "document.on.document")
                            })
                        }
#endif
                }
            }
            
            ForEach(message.attachments ?? [], id: \.id) { attachment in
                MessageFraming(message: message) {
                    AttachmentView(attachment: attachment, message: message)
                        .background(color)
                }
            }
            .frame(maxWidth: .infinity)
            
            if let attachment = message.unsentAttachment {
                MessageFraming(message: message) {
                    AttachmentView(attachment: attachment, message: message)
                        .background(color)
               }
            }
        }
            .frame(maxWidth: .infinity)
    }
}

struct MessageMetadataOverlay: View {
    let message: Message

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            #if !os(watchOS)
            if let shownTime = message.shownTime {
                Text(shownTime)
            }
            #endif
            if message.showSending {
                Image(systemName: "rays")
                    .symbolEffect(.variableColor)
            }
        }
        .font(.caption)
        .padding(.bottom, 4)
        .padding(.horizontal, 10)
    }
}

struct MessageFraming<C: View>: View {
    let message: Message
    let content: () -> C

    init(message: Message, @ViewBuilder content: @escaping () -> C) {
        self.message = message
        self.content = content
    }

    var body: some View {
        HStack {
            if message.author == .me {
                Spacer()
                content()
                    .cornerRadius(15)
                    .padding(.trailing, 10)
                #if !os(watchOS)
                    .containerRelativeFrame(
                        .horizontal, alignment: .topTrailing
                    ) { length, axis in
                        return length / 3.0 * 2.0
                    }
                #endif
            } else {
                content()
                    .cornerRadius(15)
                    .padding(.leading, 10)
                #if !os(watchOS)
                    .containerRelativeFrame(
                        .horizontal, alignment: .topLeading
                    ) { length, axis in
                        return length / 3.0 * 2.0
                    }
                #endif
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

struct SupportTypingIndicator: View {
    var body: some View {
        MessageFraming(message: Message(id: "support-typing-indicator", message: "", author: .support)) {
            TypingIndicator()
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.support)
        }
    }
}

extension Color {
    static var support: Color {
        Color.gray.opacity(0.5)
    }

    static var me: Color {
        Color.accentColor.opacity(0.5)
    }
}

private struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundColor(.gray)
                    .opacity(isAnimating ? 0.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
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

    var extraSpacing: String {
        var count: Int = 0
#if !os(watchOS)
        if let st = message.shownTime {
            count += st.count * 4 / 3 + 4
        }

        if message.showSending && message.shownTime != nil {
            count += 2
        }
        if message.showSending {
            count += 2
        }
#else
        if message.showSending {
            count += 4
        }
#endif

        if count > 0 {
            return String(repeating: " ", count: count) + "⠀"
        } else {
            return ""
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
            LinkedText(message.expandMessage() + extraSpacing)
            if message.robotMessage {
                Text("P.S. This is an auto-reply. 🤖")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
}

extension Message {
    var shownTime: String? {
        if self.showSending {
            return Date.now.formatted(date: .omitted, time: .shortened)
        }
        if self.robotMessage || self.id == "start" {
            return nil
        }
        
        let time = parseDiscordSnowflake(self.id)
        return time?.formatted(date: .omitted, time: .shortened)
    }

    var showSending: Bool {
        if self.lastSendAttempt != nil {
            return true
        }

        if !self.fetchedBackend && !self.robotMessage && self.id != "start" {
             return true
        }

        return false
    }
}

#if DEBUG
#Preview("Typing Indicator") {
    SupportTypingIndicator()
        .padding()
}

#Preview("Messaging Attachment") {
    MessageBubble(message: getAttachmentMessage(), previous: nil)
        .padding()
}

func getAttachmentMessage() -> Message {
    let m = Message(
        id: "123",
        message: "Hi Scott, this is a test message",
        author: .me,
        attachments: [Message.SentAttachment(
            id: "hi",
            data: Data(),
            filename: "diagnostics.json",
            mimetype: "application/json"
        )]
    )
    m.lastSendAttempt = .now
    return m
}

#Preview("Messaging Bubble") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi Scott, this is a test message",
        author: .me
    ), previous: nil)
        .padding()
}

#Preview("Messaging Bubble Response") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi dude, this is a response message with a https://example.com link",
        author: .support
    ), previous: nil)
        .padding()
}

#Preview("Messaging Bubble Response Robot") {
    MessageBubble(message: Message(
        id: "123",
        message: "Hi dude, this is a response message [https://test.com]",
        author: .support,
        robotMessage: true
    ), previous: nil)
        .padding()
}
#endif
