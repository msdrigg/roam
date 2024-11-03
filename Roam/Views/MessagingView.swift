//
//  MessagingView.swift
//  Roam
//
//  Created by Scott Driggers on 4/16/24.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "MessagingView"
)

func requestNotificationPermission() {
    logger.info("Requesting notification permission")
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
            logger.info("Notification permission granted.")
            getNotificationSettings()
        } else if let error {
            logger.error("Notification permission denied with error: \(error.localizedDescription)")
        }
    }
}

func getNotificationSettings() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else { return }
        DispatchQueue.main.async {
            logger.info("Registering for remote notifications")
            #if os(macOS)
                NSApplication.shared.registerForRemoteNotifications()
            #elseif !os(watchOS)
                UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }
}

@MainActor
// swiftlint:disable:next line_length force_try
let connectRegex = try! Regex("\\bconnect\\b|\\badd\\b|\\bfind my tv\\b|\\bscan\\b|\\bconnexion\\b|\\bconnecter\\b|\\btrouver ma télé\\b|\\bconectar\\b|\\bconexión\\b|\\bconecta\\b|\\bno puedo\\b|\\b无法连接\\b|\\b连接\\b|\\bconexão\\b|\\bconectar\\b|\\bnão consigo\\b|\\bkết nối\\b|\\bلا أستطيع\\b|\\bالاتصال\\b|\\bਕਨੈਕਟ\\b|\\bਹੋ ਨਹੀਂ ਸਕਦਾ\\b|\\bmaghanap ng tv\\b|\\bmagkonekta\\b|\\bverbinden\\b|\\bconnettere\\b|\\btrovare la tv\\b").ignoresCase()

struct MessageView: View {
    @State private var messageText = ""
    @Query(sort: \Message.id) private var baseMessages: [Message]
    @State private var textEditorHeight: CGFloat = 100
    @State private var refreshInterval: TimeInterval = 20
    @State private var refreshResetId = UUID()
    @State private var reportingDebugLogs = false
    @AppStorage("hasSentFirstMessage") private var hasSentFirstMessage: Bool = false
    @AppStorage("lastApnsRequestTime") private var lastApnsRequestTime: Double = -1
    @Environment(\.colorScheme) var colorScheme

    @Environment(\.createDataHandler) private var createDataHandler

    var roboMessage: Message? {

        if messageText.firstMatch(of: connectRegex) != nil {
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
            logger.info("Starting to send logs")
            let logs = await getDebugInfo(container: getSharedModelContainer())
            logger.info("Sending logs \(logs.installationInfo.userId)")

            do {
                try await uploadDebugLogs(logs: logs)
                self.sendMessageText(messageText: String(localized: "Diagnostics Shared at \(Date.now.formatted())"))
                if Locale.autoupdatingCurrent.language.languageCode?.identifier != "en" {
                    self.sendMessageText(messageText: ":ninja:\nDiagnostics Shared at \(Date.now.formatted(.iso8601))")
                }

                logger.info("Upload successful")
            } catch {
                logger.error("Failed to upload logs: \(error)")
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
                                            .frame(maxWidth: geometry.size.width * 2 / 3, alignment: .trailing)
                                            .padding(.trailing, 10)
                                    } else {
                                        MessageViewText(message)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(Color.gray.opacity(0.5))
                                            .cornerRadius(15)
                                            .frame(maxWidth: geometry.size.width * 2 / 3, alignment: .leading)
                                            .padding(.leading, 10)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .defaultScrollAnchor(.bottom)
#if !os(visionOS)
                    .scrollDismissesKeyboard(.interactively)
#endif
#if !os(tvOS)
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
                    .padding(.horizontal, 12)

                    HStack(alignment: .bottom, spacing: 10) {
                        SendDiagnosticsButton(shareDiagnostics: {reportDebugLogs()}, sharingDiagnostics: reportingDebugLogs)
#if os(macOS)
                            .padding(.bottom, 2)
#elseif os(iOS)
                            .padding(.bottom, 6)
#elseif os(visionOS)
                            .padding(.bottom, 12)
#endif

                        TextField(String(localized: "Message", comment: "Text entry field for a new message"), text: $messageText.animation(), axis: .vertical)
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
                        .animation(nil, value: messageText)

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
            #if !os(tvOS)
            .onAppear {
                UNUserNotificationCenter.current().setBadgeCount(0)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
            #endif
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
        #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func handleRefresh() async {
        while true {
            if Task.isCancelled {
                return
            }
            logger.info("Refreshing messages")
            try? await Task.sleep(nanoseconds: 1000 * 1000 * 1000)
            let latestMessageId = messages.last { $0.fetchedBackend == true }?.id

            if latestMessageId != nil {
                let createDataHandler = self.createDataHandler
                let result = await Task.detached {
                    return await createDataHandler()?.refreshMessages(
                        latestMessageId: latestMessageId,
                        viewed: true
                    ) ?? 0
                }.value
                logger.info("Got results \(result)")

                if result > 0 {
                    refreshInterval = 10
                } else {
                    if refreshInterval < 60 {
                        refreshInterval = min(refreshInterval * 2, 60)
                    }
                }
            }

            logger.info("Sleeping for \(refreshInterval)s")
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            logger.info("Done sleeping")
        }
    }

    func sendMessageText(messageText: String) {
        logger.info("Sending message \"\(messageText)\"")
        let messageCopy = messageText
        let createDataHandler = self.createDataHandler
        let latestMessageId = messages.last { $0.fetchedBackend == true }?.id
        Task {
            do {
                try await Task.detached {
                    try await sendMessage(message: messageCopy, apnsToken: nil)
                }.value

                let result = await Task.detached {
                    return await createDataHandler()?.refreshMessages(
                        latestMessageId: latestMessageId,
                        viewed: true
                    ) ?? 0
                }.value

                if result > 0 {
                    refreshResetId = UUID()
                }
            } catch {
                logger.error("Error sending message \(error)")
            }
        }
        if !hasSentFirstMessage {
            // Request notification permissions on first message
            lastApnsRequestTime = Date.now.timeIntervalSince1970
            requestNotificationPermission()
        }

        self.messageText = ""
    }

    func sendTypedMessage() {
        self.sendMessageText(messageText: messageText)
    }
}

struct SendDiagnosticsButton: View {
    let shareDiagnostics: () -> Void
    let sharingDiagnostics: Bool

    var body: some View {
        Button(action: {
            shareDiagnostics()
        }, label: {
#if os(macOS)
            Image(systemName: "paperclip")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
#else
            Label(String(localized: "Share Diagnostics", comment: "Label on a button"), systemImage: "paperclip")
                .labelStyle(.iconOnly)
#endif
        })
        .symbolEffect(.variableColor, isActive: sharingDiagnostics)
        .foregroundColor(Color.gray)
        .buttonStyle(.plain)
        .help(
            sharingDiagnostics ? "Sharing diagnostics..." :
            "Share diagnostics"
        )

    }
}

#if os(macOS)
    import AppKit

    struct EmojiPicker: View {
        var body: some View {
            Button(action: {
                NSApp.orderFrontCharacterPalette(nil)
            }, label: {
                Image(systemName: "face.smiling")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color.gray)
            })
            .buttonStyle(PlainButtonStyle())
        }
    }

#endif

#if DEBUG
#Preview("Message View") {
    MessageView()
        .modelContainer(previewContainer)
}
#endif
