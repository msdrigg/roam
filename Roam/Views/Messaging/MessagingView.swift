
import Foundation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
// swiftlint:disable:next line_length force_try
private let connectRegex = try! Regex("\\bconne|\\badd|\\bfind my tv\\b|\\bscan|\\bencuentra|\\btrouver ma télé\\b|\\bconexión\\b|\\bconecta\\b|\\bno puedo\\b|\\b无法连接\\b|\\b连接\\b|\\bconexão\\b|\\bconectar\\b|\\bnão consigo\\b|\\bkết nối\\b|\\bلا أستطيع\\b|\\bالاتصال\\b|\\bਕਨੈਕਟ\\b|\\bਹੋ ਨਹੀਂ ਸਕਦਾ\\b|\\bmaghanap ng tv\\b|\\bmagkonekta\\b|\\bverbinden\\b|\\btrovare la tv\\b").ignoresCase()

struct MessageView: View {
    @State private var messageFieldText = ""
    @Query(sort: \Message.id) private var baseMessages: [Message]
    @State private var textEditorHeight: CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @State private var reportingDebugLogs = false
    @AppStorage("hasSentFirstMessage") private var hasSentFirstMessage: Bool = false
    @AppStorage("lastApnsRequestTime") private var lastApnsRequestTime: Double = -1
    @Environment(\.colorScheme) var colorScheme

#if !os(watchOS)
    @EnvironmentObject private var appDelegate: RoamAppDelegate
#endif

    var roboMessage: Message? {
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

    var messages: [Message] {
        (
            [Message(
                id: "start",
                message: String(
                    localized: "Hi, I'm Scott. I make Roam. What's on your mind? I'll do my best to respond to these messages as quick as I can.",
                    comment: "First message to user in a chat"
                ),
                author: .support,
                fetchedBackend: false
            )]
            + baseMessages
            + [roboMessage].compactMap({$0})
        ).filter { !$0.message.isEmpty }
    }

    func reportDebugLogs() {
        Task {
            reportingDebugLogs = true
            defer {
                reportingDebugLogs = false
            }
            Log.userInteraction.notice("Starting to send logs")
            let logs = await getDebugInfo(container: getSharedModelContainer())
            Log.userInteraction.notice("Sending logs \(logs.installationInfo.userId, privacy: .public)")

            do {
                try await uploadDebugLogs(logs: logs)
                self.sendMessageText(messageText: String(localized: "Diagnostics Shared at \(Date.now.formatted())"))
                if Locale.autoupdatingCurrent.language.languageCode?.identifier != "en" {
                    self.sendMessageText(messageText: ":ninja:\nDiagnostics Shared at \(Date.now.formatted(.iso8601))")
                }

                Log.userInteraction.notice("Upload successful")
            } catch {
                Log.userInteraction.error("Failed to upload logs: \(error, privacy: .public)")
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                ScrollViewReader { scrollValue in
                    ScrollView {
                        LazyVStack {
                            ForEach(messages, id: \.id) { message in
                                MessageBubble(message: message)
                                    .frame(maxWidth: geometry.size.width * 2 / 3, alignment: .trailing)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .defaultScrollAnchor(.bottom)
#if !os(visionOS)
                    .scrollDismissesKeyboard(.interactively)
#endif
                    .textSelection(.enabled)
                    .onChange(of: messages.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let id = messages.last?.id {
                                withAnimation(.easeInOut) {
                                    scrollValue.scrollTo(id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)

                    HStack(alignment: .bottom, spacing: 10) {
                        SendDiagnosticsButton(shareDiagnostics: {reportDebugLogs()}, sharingDiagnostics: reportingDebugLogs)
#if os(macOS)
                            .padding(.bottom, 3)
#elseif os(iOS)
                            .padding(.bottom, 4)
#elseif os(visionOS)
                            .padding(.bottom, 12)
#endif

                        TextField(String(localized: "Message", comment: "Text entry field for a new message"), text: $messageFieldText.animation(), axis: .vertical)
                            .onSubmit {
                                sendTypedMessage()
                            }
                            .font(.system(.body))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .lineLimit(1 ... 8)
                            .textFieldStyle(PlainTextFieldStyle())
                            .background(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary, lineWidth: 2)
                            .background(Color.clear))
                            .scrollIndicators(.hidden)
#if os(visionOS)
                            .padding(.bottom, 6)
#endif
                            .animation(nil, value: messageFieldText)

#if os(macOS)
                        EmojiPicker().padding(.bottom, 2)
#else
                        Button(action: sendTypedMessage) {
                            Label(String(localized: "Send", comment: "Label on a button to send a message"), systemImage: "arrow.up")
                        }
                            .buttonBorderShape(.circle)
                            .buttonStyle(.borderedProminent)
                            .labelStyle(.iconOnly)
                            .help(String(localized: "Send the message", comment: "Help text on a button to send a chat message"))
                        #if os(visionOS)
                            .padding(.bottom, 2)
                        #endif

#endif
                    }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                }
            }
            .onAppear {
                UNUserNotificationCenter.current().setBadgeCount(0)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
#if !os(watchOS)
            .onAppear {
                appDelegate.navigationPath.showingMessagesView = true
            }
            .onDisappear {
                appDelegate.navigationPath.showingMessagesView = false
            }
#endif

        }
        .onAppear {
            Log.lifecycle.notice("Showing message view")
        }
        .onDisappear {
            Log.lifecycle.notice("Closing message view")
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
        .navigationTitle(String(localized: "Messages", comment: "Window header for the messages window"))
        .task(id: refreshResetId) {
            refreshInterval = 10
            await handleRefresh()
        }
        #if os(macOS)
        .frame(minHeight: 200)
        .frame(width: 400)
        #endif
        .navigationTitle(String(localized: "Messages", comment: "Window header for the messages window"))
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func handleRefresh() async {
        while true {
            if Task.isCancelled {
                return
            }
            Log.userInteraction.notice("Refreshing messages")
            try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
            let latestMessageId = messages.last { $0.fetchedBackend == true }?.id

            if latestMessageId != nil {
                let result = await Task.detached {
                    return await DataHandler(modelContainer: getSharedModelContainer()).refreshMessages(
                        latestMessageId: latestMessageId,
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
            Log.userInteraction.notice("Done sleeping")
        }
    }

    func sendMessageText(messageText: String) {
        Log.userInteraction.notice("Sending message \"\(messageText, privacy: .public)\"")
        let messageCopy = messageText
        let latestMessageId = messages.last { $0.fetchedBackend == true }?.id
        Task {
            do {
                try await Task.detached {
                    try await sendMessage(message: messageCopy, apnsToken: nil)
                }.value

                let result = await Task.detached {
                    return await DataHandler(modelContainer: getSharedModelContainer()).refreshMessages(
                        latestMessageId: latestMessageId,
                        viewed: true
                    )
                }.value

                if result > 0 {
                    refreshResetId = UUID()
                }
            } catch {
                Log.userInteraction.error("Error sending message \(error, privacy: .public)")
            }
        }
        if !hasSentFirstMessage {
            // Request notification permissions on first message
            lastApnsRequestTime = Date.now.timeIntervalSince1970
            requestNotificationPermission()
        }
    }

    func sendTypedMessage() {
        self.sendMessageText(messageText: messageFieldText)
        self.messageFieldText = ""

    }
}

#if DEBUG
#Preview("Message View") {
    MessageView()
        .modelContainer(previewContainer)
}
#endif
