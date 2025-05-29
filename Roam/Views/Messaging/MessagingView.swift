import Foundation
import UniformTypeIdentifiers
import SwiftData
import UserNotifications
import SwiftUI

typealias ItemProvider = NSItemProvider

struct MessageView: View {
    @State private var messageFieldText = ""
    @State private var attachedFiles: [SelectedAttachment] = []

    @Query(sort: \Message.id) private var baseMessages: [Message]
    @State private var textEditorHeight: CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @State private var keyboardIsShowing = false
    @State private var wrongAttemptsTracker = WrongAttemptsTracker()
    @AppStorage(UserDefaultKeys.hasSentFirstMessage) private var hasSentFirstMessage: Bool = false
    @AppStorage(UserDefaultKeys.lastApnsRequestTime) private var lastApnsRequestTime: Double = -1
    @AppStorage(UserDefaultKeys.lastSupportTypingTime) private var lastSupportTypingTimeInterval: TimeInterval = Date.distantPast.timeIntervalSince1970
    @State private var lastSelfTypingTime: Date = Date.distantPast
    @Environment(\.colorScheme) var colorScheme

    private var showSupportTypingIndicator: Bool {
        let lastSupportTypingDate = Date(timeIntervalSince1970: lastSupportTypingTimeInterval)

        if lastSupportTypingDate > Date.now.addingTimeInterval(-8) {
            if let lastSupportMessage = baseMessages.last(where: { $0.author == .support })?.timestamp {
                return lastSupportMessage < lastSupportTypingDate.addingTimeInterval(-2)
            } else {
                return true
            }
        } else {
            return false
        }
    }
    #if !os(watchOS)
    @EnvironmentObject private var appDelegate: RoamAppDelegate
    #endif

    var roboMessage: Message? {
        // swiftlint:disable:next line_length force_try
        let connectRegex = try! Regex("\\bconne|\\badd|\\bpair|\\bfind my tv\\b|\\bscan|\\bencuentra|\\bpick up|\\btrouver ma télé\\b|\\bconexión\\b|\\bconecta\\b|\\bsuche|\\bauftauch|\\bno puedo\\b|\\b无法连接\\b|\\b连接\\b|\\bconexão\\b|\\bconectar\\b|\\bnão consigo\\b|\\bkết nối\\b|\\bلا أستطيع\\b|\\bالاتصال\\b|\\bਕਨੈਕਟ\\b|\\bਹੋ ਨਹੀਂ ਸਕਦਾ\\b|\\bmaghanap ng tv\\b|\\bmagkonekta\\b|\\bverbinden\\b|\\btrovare la tv\\b|اشغل").ignoresCase()
        if messageFieldText.firstMatch(of: connectRegex) != nil {
            return Message(
                id: "connect-help",
                message: String(localized: "If Roam isn't auto-discovering your tv, check this guide to manually add your TV: https://roam.msd3.io/manually-add-tv/"),
                author: .support,
                fetchedBackend: false,
                messageTitle: String(localized: "Are you having trouble connecting your TV?"),
                robotMessage: true
            )
        } else {
            return nil
        }
    }

    var pendingAttachments: Bool {
        attachedFiles.contains{ $0.failure != nil || $0.attachment == nil}
    }

    var messages: [Message] {
        (
            [Message(
                id: "start",
                message: String(
                    localized: "Hi, I'm Scott. I make the Roam app. What's on your mind? I'll do my best to respond to these messages as quick as I can.",
                    comment: "First message to user in a chat"
                ),
                author: .support,
                fetchedBackend: false
            )]
            + baseMessages
                .filter{!$0.hidden}
            + [roboMessage].compactMap({$0})
        ).filter { !$0.message.isEmpty || !$0.attachments.isEmpty || $0.unsentAttachment != nil }
    }

    var zippedMessages: [(Message, Message?)] {
        Array(zip(messages, [nil] + messages.dropLast()))
    }

    func notifyTyping() {
        if self.lastSelfTypingTime > Date().addingTimeInterval(-5) {
            Log.userInteraction.notice("Not sending typing notification because last sent \(-self.lastSelfTypingTime.timeIntervalSinceNow, privacy: .public)) s ago")
            return
        }
        self.lastSelfTypingTime = Date.now
        Task {
            do {
                try await sendTyping()
                Log.userInteraction.notice("Sent typing notification \(Date.now, privacy: .public)")
            } catch {
                Log.userInteraction.notice("Error sending typing notification \(error, privacy: .public)")
            }
        }
    }

    var body: some View {
        if runningInPreview {
            bodyContent
        } else {
            bodyContent
            #if os(iOS)
                .onReceive(KeyboardReadable.keyboardPublisher) { kbVisible in
                    withAnimation {
                        keyboardIsShowing = kbVisible
                    }
                }
            #endif
            #if !os(watchOS)
                .onDrop(of: [UTType.image, UTType.json, UTType.text, UTType.pdf, UTType.movie, .archive], isTargeted: nil, perform: { providers, _ in
                    Log.userInteraction.notice("Got drop \(providers, privacy: .public)")

                    return self.handleProviders(providers)
                })
            #endif
                .onAppear {
                    #if !os(watchOS)
                    UNUserNotificationCenter.current().setBadgeCount(0)
                    #endif
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                }

#if os(macOS)
                .onWindowFocused {
                    Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")

                    appDelegate.navigationPath.focusedWindow = .messages
                }
#elseif !os(watchOS)
                .onAppear {
                    appDelegate.navigationPath.focusedWindow = .messages
                }
#endif
                .onAppear {
                    Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
                }
                .onDisappear {
                    Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
                }
                .onChange(of: messageFieldText, initial: false) {
                    if !messageFieldText.isEmpty {
                        notifyTyping()
                    }
                }
                .task(id: hasSentFirstMessage) {
                    if !hasSentFirstMessage {
                        return
                    }
                    if lastApnsRequestTime < Date.now.timeIntervalSince1970 - 3600 * 24 {
                        lastApnsRequestTime = Date.now.timeIntervalSince1970
                        requestNotificationPermission()
                    }
                }
                .task(id: refreshResetId) {
                    refreshInterval = 10
                    await handleRefresh()
                }
                .navigationTitle(String(localized: "Messages", comment: "Window header for the messages window"))
                #if os(macOS)
                .frame(minHeight: 200)
                .frame(width: 400)
                #endif
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    @ViewBuilder
    var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            AttachButton(handleAttachment: { attachment in
                self.handleAttachment(attachment)
            })
#if os(macOS)
                .padding(.bottom, 3)
#elseif os(iOS) || os(watchOS)
                .padding(.bottom, 4)
#elseif os(visionOS)
                .padding(.bottom, 20)
#endif

            VStack(spacing: 0) {
#if !os(watchOS)
                if attachedFiles.count > 0 {
                    AttachmentRow(attachments: $attachedFiles)
                        .environment(wrongAttemptsTracker)
                }
#endif
                #if os(watchOS)
                TextFieldLink(prompt: Text("Message", comment: "Text entry field for a new message")) {
                    HStack {
                        Spacer()
                        Text("Chat \(Image(systemName: "keyboard"))", comment: "Text entry field for a new message")
                        Spacer()
                    }
                        .imageScale(.large)
                        .font(.caption.leading(.loose))
                        .foregroundStyle(.foreground)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.8))
                        .clipShape(Capsule())
                        .tint(Color.accentColor)
                } onSubmit: { text in
                    sendMessageText(messageText: text)
                }
                .buttonStyle(.borderless)
                #else
                TextField(String(localized: "Message", comment: "Text entry field for a new message"), text: $messageFieldText.animation(), axis: .vertical)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .onSubmit {
                        sendTypedMessage()
                    }
                    .font(.body.leading(.loose))
                    .lineLimit(1 ... 8)
                    .scrollIndicators(.hidden)
                    .animation(nil, value: messageFieldText)
#if os(visionOS)
                    .textFieldStyle(PaddedRoundedTextFieldStyle())
                    .controlSize(.large)
                    .padding(.bottom, 6)
#else
                    .textFieldStyle(PlainTextFieldStyle())
#endif
                #endif
            }
#if !os(watchOS)
                .padding(4)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.secondary, lineWidth: 2)
                        .background(Color.clear)
                )
#endif

#if os(macOS)
            EmojiPicker().padding(.bottom, 2)
#elseif !os(watchOS)
            Button(action: sendTypedMessage) {
                Label(String(localized: "Send", comment: "Label on a button to send a message"), systemImage: "arrow.up")
            }
            .buttonBorderShape(.circle)
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .help(String(localized: "Send the message", comment: "Help text on a button to send a chat message"))
#if os(visionOS)
            .padding(.bottom, 12)
#endif
#endif
        }
        .padding(.horizontal)
        .padding(.top, 12)
#if os(iOS)
        .padding(.bottom, keyboardIsShowing ? 0 : 18)
        .safeAreaPadding(.bottom)
#else
        .padding(.bottom, 16)
#endif
#if os(macOS) || os(watchOS)
        .background(
            Material.thin
        )
#else
        .background(
            Material.bar
        )
#endif
    }

    @ViewBuilder
    var bodyContent: some View {
        VStack(spacing: 0) {
            messageList

            bottomBar
        }
#if !os(macOS)
        .ignoresSafeArea(
            .container,
            edges: .bottom
        )
#endif
#if os(macOS)
        .background(
            .thickMaterial
        )
#endif
    }

    @ViewBuilder
    var messageList: some View {
        ScrollViewReader { scrollValue in
            ScrollView {
                LazyVStack {
                    ForEach(zippedMessages, id: \.0.id) { (message, previous) in
                        MessageBubble(message: message, previous: previous)
                    }
                    if showSupportTypingIndicator {
                        SupportTypingIndicator()
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
            .defaultScrollAnchor(.bottom)
#if !os(visionOS)
            .scrollDismissesKeyboard(.interactively)
#endif
#if !os(watchOS)
            .textSelection(.enabled)
#endif
            .onChange(of: messages.count) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let id = messages.last?.id {
                        withAnimation(.easeInOut) {
                            scrollValue.scrollTo(id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func handleRefresh() async {
        while true {
            if Task.isCancelled {
                return
            }
            Log.userInteraction.notice("Refreshing \("messages", privacy: .public)")
            try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
            let latestMessageId = messages.last { $0.fetchedBackend == true }?.id

            if latestMessageId != nil {
                let result = await Task {
                    return await MessageDataHandler.shared.refreshMessages(
                        viewed: true
                    )
                }.value
                Log.userInteraction.notice("Got results \(result, privacy: .public)")

                if result > 0 {
                    refreshInterval = 10
                } else {
                    if refreshInterval < 60 {
                        refreshInterval = min(refreshInterval * 2, 60)
                    }
                }
            }

            Log.userInteraction.notice("Sleeping for \(refreshInterval, privacy: .public)s")
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
        }
    }

    #if !os(watchOS)
    private func handleProviders(_ providers: [ItemProvider]) -> Bool {
        var anySucceeded = false
        for provider in providers {
            let attachmentCount = self.attachedFiles.count(where: {
                $0.name.starts(with: /attachment\s*\d*/.ignoresCase())
            })
            let name = if attachmentCount == 0 {
                "Attachment"
            } else {
                "Attachment \(attachmentCount + 1)"
            }

            if let attachment = ItemProviderAttachment(provider, name: name) {
                self.handleAttachment(attachment)
                anySucceeded = true
            }
        }

        return anySucceeded
    }
    #endif

    private func handleAttachment(_ attachment: any PendingAttachment) {
        self.attachedFiles.append(SelectedAttachment(attachment: nil, name: attachment.filename, type: attachment.utType, failure: nil, loading: true, id: attachment.id))
        Task {
            let result = await attachment.load()
            switch result {
            case .success(let result):
                Log.userInteraction.warning("Loaded attachment \(attachment.filename, privacy: .public) - \(attachment.id, privacy: .public)")

                DispatchQueue.main.async {
                    self.attachedFiles = self.attachedFiles.map { file in
                        if file.id == attachment.id {
                            if result.dataSize > 1000000 * 10 - 2000 {
                                let error = AttachmentError.fileTooLarge(Int(result.dataSize))
                                Log.userInteraction.warning("Error, unable to load attachment \(attachment.filename, privacy: .public): Too large \(error)")
                                return file.withAttachment(result).withError(error)
                            } else {
                                return file.withAttachment(result)
                            }
                        } else {
                            return file
                        }
                    }
#if os(watchOS)
                    self.messageFieldText = String(localized: "Shared Diagnostics")
                    self.sendTypedMessage()
#endif
                }
            case .failure(let error):
                Log.userInteraction.warning("Error, unable to load attachment \(attachment.filename, privacy: .public): \(error, privacy: .public)")

#if !os(watchOS)
                DispatchQueue.main.async {
                    self.attachedFiles = self.attachedFiles.map{ file in
                        if file.id == attachment.id {
                            return file.withError(error)
                        } else {
                            return file
                        }
                    }
                }
#endif
            }
        }
    }

    private func sendMessageText(messageText: String, attachment: AttachmentUpload? = nil) {
        let messageCopy = messageText
        if messageCopy.isEmpty && attachment == nil {
            return
        }
        Log.userInteraction.notice("Sending message \"\(messageText, privacy: .public)\" with attachment \(attachment?.filename ?? "--", privacy: .public) attachments")
        Task {
            do {
                try await MessageDataHandler.shared.sendChatMessage(message: messageCopy, attachment: attachment)

                Task {
                    let result = await MessageDataHandler.shared.refreshMessages(
                        viewed: true
                    )
                    if result > 0 {
                        refreshResetId = UUID()
                    }
                }
            } catch {
                Log.userInteraction.error("Error sending message \(error, privacy: .public)")
            }
        }
        if !hasSentFirstMessage {
            lastApnsRequestTime = Date.now.timeIntervalSince1970
            requestNotificationPermission()
        }
    }

    private func sendTypedMessage() {
        if attachedFiles.contains(where: {$0.failure != nil || $0.loading}) {
            wrongAttemptsTracker.attempts += 1
            return
        }
        let firstAttachment = attachedFiles.first?.attachment
        self.sendMessageText(messageText: messageFieldText, attachment: firstAttachment)
        for attachment in attachedFiles.dropFirst() {
            self.sendMessageText(messageText: "", attachment: attachment.attachment)
        }
        self.messageFieldText = ""
        self.attachedFiles = []
        self.lastSelfTypingTime = Date.distantPast
    }
}

#if DEBUG
#Preview(
    "Message View",
    traits: .fixedLayout(width: 400, height: 300)
) {
    MessageView()
        .modelContainer(previewContainer)
}

#Preview(
    "Message List",
    traits: .fixedLayout(width: 400, height: 100)
) {
    Group {
        MessageView()
            .messageList
    }
        .modelContainer(previewContainer)
}
#endif
