import Foundation
import UniformTypeIdentifiers
import UserNotifications
import SwiftUI

typealias ItemProvider = NSItemProvider

struct MessageView: View {
    @State private var messageFieldText = ""
    @State private var attachedFiles: [SelectedAttachment] = []

    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    @State private var textEditorHeight: CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @State private var keyboardIsShowing = false
    @State private var wrongAttemptsTracker = WrongAttemptsTracker()
    // Distinct haptics for the three ways a send tap can end, so it is possible
    // to tell a tap that did nothing from a tap that never arrived without
    // reading a log: a real send taps once, a blocked one buzzes an error.
    @State private var sendTriggeredCounter = 0
    @State private var sendBlockedCounter = 0
    @State private var sendEmptyCounter = 0
    @State private var celebration = CelebrationController()
    @State private var tipStore = TipStore.shared
    @AppStorage(UserDefaultKeys.hasSentFirstMessage) private var hasSentFirstMessage: Bool = false
    @AppStorage(UserDefaultKeys.lastApnsRequestTime) private var lastApnsRequestTime: Double = -1
    @AppStorage(UserDefaultKeys.lastSupportTypingTime) private var lastSupportTypingTimeInterval: TimeInterval = Date.distantPast.timeIntervalSince1970
    @State private var lastSelfTypingTime: Date = Date.distantPast
    @Environment(\.colorScheme) var colorScheme
    @AppStorageColor(UserDefaultKeys.customAccentColor) private var meColor: Color = .accentColor

    private var showSupportTypingIndicator: Bool {
        let lastSupportTypingDate = Date(timeIntervalSince1970: lastSupportTypingTimeInterval)

        if lastSupportTypingDate > Date.now.addingTimeInterval(-8) {
            if let lastSupportMessage = messageLoader.messages?.last(where: { $0.author == .support })?.timestamp {
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
        if let roboMessage = checkRoboMessage(messageFieldText) {
            switch roboMessage {
            case .cantConnect:
                return Message(
                    id: "connect-help",
                    message: String(localized: "If Roam isn't auto-discovering your tv, check this guide to manually add your TV: https://roam.msd3.io/manually-add-tv/"),
                    author: .support,
                    fetchedBackend: false,
                    messageTitle: String(localized: "Are you having trouble connecting your TV?"),
                    robotMessage: true
                )
            case .thirdPartyApps:
                #if os(watchOS)
                return Message(
                    id: "third-party-apps-help",
                    message: String(localized: "If Roam isn't auto-discovering your tv, check this guide to manually add your TV: https://roam.msd3.io/manually-add-tv/"),
                    author: .support,
                    fetchedBackend: false,
                    messageTitle: String(localized: "Are you having trouble control your TV?"),
                    robotMessage: true
                )
                #else
                return nil
                #endif
            }
        } else {
            return nil
        }
    }

    /// True once support has sent the unlock code into this conversation.
    ///
    /// Read off the loader's raw list rather than `messages`, because the code
    /// itself is a hidden message and `messages` has already filtered it out.
    private var receivedDeveloperUnlockCode: Bool {
        (messageLoader.messages ?? []).contains { message in
            message.author == .support && TipStore.isDeveloperUnlockCode(message.message)
        }
    }

    /// Pinned to the end of the conversation for as long as the developer
    /// unlock is active, so the Celebrate button stays reachable instead of
    /// being a one-frame confirmation the user can never get back to.
    var developerUnlockMessage: Message? {
        guard tipStore.isDeveloperUnlocked else { return nil }

        return Message(
            id: Message.developerUnlockID,
            message: String(
                localized: "Developer unlocked tip-based functionality",
                comment: "Confirmation shown in the chat when support sends the developer unlock code"
            ),
            author: .support,
            fetchedBackend: false
        )
    }

    var pendingAttachments: Bool {
        attachedFiles.contains{ $0.failure != nil || $0.attachment == nil}
    }

    var messages: [Message] {
        (
            [Message(
                id: "start",
                message: String(
                    // swiftlint:disable:next line_length
                    localized: "Hi, I'm Scott. I make the Roam app. What's on your mind? I'll do my best to respond to these messages as quick as I can. I've asked a virtual assistant to do an initial followup to get you the fastest response, but I read every message personally!",
                    comment: "First message to user in a chat"
                ),
                author: .support,
                fetchedBackend: false
            )]
            + (messageLoader.messages ?? [])
                .filter{!$0.hidden}
            + [developerUnlockMessage].compactMap({$0})
            + [roboMessage].compactMap({$0})
        ).filter { !$0.message.isEmpty || !$0.sentAttachments.isEmpty || $0.unsentAttachment != nil }
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
                    Task {
                        try? await RoamDataHandler.shared.markMessagesViewed()
                    }
                }

#if os(macOS)
                .onWindowFocused {
                    Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")

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
                // `initial: true` so a code that arrived while the user was
                // elsewhere in the app still lands the moment they open the
                // chat. `redeemDeveloperUnlock` only reports true the once, so
                // reopening the chat later doesn't re-fire the confetti.
                .onChange(of: receivedDeveloperUnlockCode, initial: true) { _, received in
                    guard received, tipStore.redeemDeveloperUnlock() else { return }
                    celebration.celebrate()
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
        bottomBarContent
#if !os(visionOS)
            // On the bar rather than the button so the same feedback covers the
            // text field's `onSubmit` and the macOS/watchOS send paths too.
            .sensoryFeedback(.impact, trigger: sendTriggeredCounter)
            .sensoryFeedback(.error, trigger: sendBlockedCounter)
            .sensoryFeedback(.warning, trigger: sendEmptyCounter)
#endif
    }

    @ViewBuilder
    var bottomBarContent: some View {
#if os(iOS)
        iosBottomBar
#else
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
                        .background(meColor.opacity(0.8))
                        .clipShape(Capsule())
                        .tint(meColor)
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
#endif
    }

#if os(iOS)
    // MARK: - iOS floating input bar
    //
    // A liquid-glass capsule "input group" (paperclip Attach + text field) sits
    // beside a separate liquid-glass prominent Send circle. The bar itself has no
    // background - only the capsule and the circle carry glass - so it reads as
    // two floating controls hovering above the keyboard.

    @ViewBuilder
    private var iosBottomBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            inputGroup
            sendButton
        }
        .glassContainerIfSupported(spacing: 8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, keyboardIsShowing ? 8 : 4)
    }

    @ViewBuilder
    private var inputGroup: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) {
            if attachedFiles.count > 0 {
                AttachmentRow(attachments: $attachedFiles)
                    .environment(wrongAttemptsTracker)
            }
            HStack(alignment: .bottom, spacing: 2) {
                AttachButton(
                    handleAttachment: { attachment in
                        self.handleAttachment(attachment)
                    },
                    systemImage: "paperclip",
                    iconColor: .secondary,
                    iconPointSize: 20
                )
                .padding(.leading, 12)
                .padding(.bottom, 9)

                TextField(
                    String(localized: "Message", comment: "Text entry field for a new message"),
                    text: $messageFieldText.animation(),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.body.leading(.loose))
                .lineLimit(1 ... 8)
                .scrollIndicators(.hidden)
                .animation(nil, value: messageFieldText)
                .onSubmit {
                    sendTypedMessage()
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }
        }
        .messageInputGlass(in: shape)
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: sendTypedMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                // Without this the tappable area is whatever the glass layout
                // last resolved, which goes stale while the keyboard is up: the
                // glass still reacts to the touch but the action never runs.
                // Pinning it to the drawn circle keeps the hit region on the
                // button itself rather than the container's cached geometry.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sendButtonGlass(tint: meColor)
        // Icon-only, so the automatic symbol-derived label ("arrow up") is what
        // VoiceOver would otherwise read out.
        .accessibilityLabel(Text("Send", comment: "Label on a button to send a message"))
        .help(String(localized: "Send the message", comment: "Help text on a button to send a chat message"))
    }
#endif

    @ViewBuilder
    var bodyContent: some View {
        conversation
            // Above the bubbles so the Celebrate button can reach it, and above
            // the input bar so confetti falls in front of everything.
            .environment(celebration)
            .confettiOverlay(burst: celebration.burst)
    }

    @ViewBuilder
    private var conversation: some View {
#if os(iOS)
        // The input bar floats in the bottom safe area so chat content scrolls
        // *behind* its liquid glass rather than sitting on an opaque bar. The
        // safe-area inset also keeps the last message clear of the bar and lifts
        // the whole group above the keyboard when it appears.
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
#else
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
#endif
    }

    @ViewBuilder
    var messageList: some View {
        ScrollViewReader { scrollValue in
            ScrollView {
                LazyVStack {
                    ForEach(zippedMessages, id: \.0.id) { (message, previous) in
                        MessageBubble(message: message, previous: previous, onRetry: retryMessage)
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
            if hasSentFirstMessage || messages.contains(where: { $0.fetchedBackend }) {
                let result = await RoamDataHandler.shared.refreshMessages(viewed: true)
                Log.userInteraction.notice("Got \(result, privacy: .public) message updates")

                if result > 0 {
                    refreshInterval = 10
                } else if refreshInterval < 60 {
                    refreshInterval = min(refreshInterval * 2, 60)
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

    private func retryMessage(id: String) {
        Log.userInteraction.notice("Retrying a failed message id=\(id, privacy: .public)")
        Task {
            await RoamDataHandler.shared.retrySendingMessage(id: id)
            let result = await RoamDataHandler.shared.refreshMessages(viewed: true)
            if result > 0 {
                refreshResetId = UUID()
            }
        }
    }

    private func sendMessageText(messageText: String, attachment: AttachmentUpload? = nil) {
        let messageCopy = messageText
        if messageCopy.isEmpty && attachment == nil {
            Log.userInteraction.notice("Ignoring empty message send with no attachment")
            sendEmptyCounter += 1
            return
        }
        let attachmentSummary = attachment.map { attachment in
            "\(attachment.filename) id=\(attachment.id) hash=\(attachment.dataHash) bytes=\(attachment.dataSize) type=\(attachment.contentType)"
        } ?? "none"
        Log.userInteraction.notice("Sending message \"\(messageText, privacy: .public)\" contentBytes=\(messageCopy.utf8.count, privacy: .public) attachment=\(attachmentSummary, privacy: .public)")
        Task {
            do {
                Log.userInteraction.notice("Message send task started attachment=\(attachment?.filename ?? "--", privacy: .public)")
                try await RoamDataHandler.shared.sendChatMessage(message: messageCopy, attachment: attachment)
                Log.userInteraction.notice("Message send task completed; refreshing messages")

                let result = await RoamDataHandler.shared.refreshMessages(viewed: true)
                Log.userInteraction.notice("Message send refresh completed newMessageCount=\(result, privacy: .public)")
                if result > 0 {
                    refreshResetId = UUID()
                }
            } catch is CancellationError {
                Log.userInteraction.error("Message send task cancelled attachment=\(attachment?.filename ?? "--", privacy: .public)")
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
        // Instrumentation for "send does nothing": this line firing proves the
        // button's action ran at all, which a stale hit region would prevent.
        // The block below used to return silently, so a pinned attachment and a
        // dead button were indistinguishable in the logs.
        Log.userInteraction.notice(
            "Send tapped contentBytes=\(messageFieldText.utf8.count, privacy: .public) attachedFiles=\(attachedFiles.count, privacy: .public) keyboardIsShowing=\(keyboardIsShowing, privacy: .public)"
        )
        if let blocker = attachedFiles.first(where: {$0.failure != nil || $0.loading}) {
            Log.userInteraction.error(
                "Send blocked by attachment name=\(blocker.name, privacy: .public) id=\(blocker.id, privacy: .public) loading=\(blocker.loading, privacy: .public) failure=\(blocker.failure ?? "--", privacy: .public)"
            )
            wrongAttemptsTracker.attempts += 1
            sendBlockedCounter += 1
            return
        }
        sendTriggeredCounter += 1
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

#if os(iOS)
private extension View {
    /// Liquid glass for the message input capsule, with a frosted-material
    /// fallback for the iOS 18–25 deployment range. Non-interactive so the glass
    /// doesn't add a press reaction to the text-entry area.
    @ViewBuilder
    func messageInputGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    /// Liquid glass for the prominent Send circle, tinted with the accent color.
    /// Falls back to a solid accent fill on iOS 18–25.
    @ViewBuilder
    func sendButtonGlass(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: Circle())
        } else {
            self.background(tint, in: Circle())
        }
    }
}
#endif

#if DEBUG
#Preview(
    "Message View",
    traits: .sampleData, .fixedLayout(width: 400, height: 300)
) {
    MessageView()
}

#Preview(
    "Message List",
    traits: .sampleData, .fixedLayout(width: 400, height: 100)
) {
    Group {
        MessageView()
            .messageList
    }
}
#endif
