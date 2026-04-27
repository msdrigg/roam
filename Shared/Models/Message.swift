import Foundation
import CoreTransferable
import UniformTypeIdentifiers

public struct Message: Codable, Sendable {
    let id: String
    var message: String
    var author: AuthorType
    var viewed: Bool = false
    var hidden: Bool = false
    var fetchedBackend: Bool
    var lastSendAttempt: Date?
    var nonce: String?
    var sentAttachments: [SentAttachment]
    var unsentAttachment: AttachmentUpload?
    var messageTitle: String?
    var robotMessage: Bool = false
    var aiMessage: Bool = false
    var humanSupportMessage: Bool = false

    enum AuthorType: String, Codable {
        case me
        case support
    }

    struct SentAttachment: Codable, Hashable {
        let id: String
        let dataHash: String
        let dataSize: Int64
        let filename: String
        let mimetype: String
    }

    init(
        id: String, message: String, author: AuthorType,
        fetchedBackend: Bool = true, viewed: Bool = false,
        attachments: [SentAttachment] = [], unsentAttachment: AttachmentUpload? = nil,
        nonce: String? = nil, messageTitle: String? = nil,
        robotMessage: Bool = false,
        aiMessage: Bool = false,
        humanSupportMessage: Bool = false
    ) {
        self.id = id
        self.message = message
        self.author = author
        self.fetchedBackend = fetchedBackend
        self.viewed = viewed
        self.hidden = isHiddenMessage(message)
        self.nonce = nonce
        self.unsentAttachment = unsentAttachment
        self.messageTitle = messageTitle
        self.robotMessage = robotMessage
        self.aiMessage = aiMessage
        self.humanSupportMessage = humanSupportMessage

        self.sentAttachments = attachments
    }

    // Helper methods for attachment handling
    func getAttachments() -> [SentAttachment] {
        return self.sentAttachments
    }

    func getUnsentAttachment() -> AttachmentUpload? {
        return self.unsentAttachment
    }
}

extension Message {
    var timestamp: Date? {
        return parseDiscordSnowflake(self.id)
    }

    mutating func cycleAttachments(_ attachments: [Message.SentAttachment]) {
        self.sentAttachments = attachments
        unsentAttachment = nil
    }

    func triggerAction() {
#if !WIDGET
        if self.message.hasPrefix(":command-share-diagnostics:") || self.message.hasPrefix(":command_share_diagnostics:") {
            Task {
                do {
                    let upload = try await DiagnosticsImport(userInitiated: false).load().get()
                    try await RoamDataHandler.shared.sendChatMessage(message: ":ninja:", attachment: upload)
                    Log.backend.notice("Sent attachment to share diagnostics \(String(describing: upload), privacy: .public)")
                } catch {
                    Log.backend.warning("Error sending diagnostics on command-share: \(error, privacy: .public)")
                }
            }
        }
#endif
    }

    func expandMessage() -> String {
        return expandMessagingText(self.message)
    }
}

#if !WIDGET
extension Message {
    init(_ message: MessageModelResponse) {
        self.init(
            id: message.id,
            message: message.message,
            author: message.author,
            attachments: message.attachments?.compactMap({ attachment in
                let hash = fastHashData(data: attachment.data)
                do {
                    try storeAttachmentToDisk(attachmentData: attachment.data, hash: hash, filename: attachment.filename)
                } catch {
                    Log.backend.error("Error saving attachment to disk \(error, privacy: .public)")
                    return nil
                }
                return Message.SentAttachment(
                    id: attachment.id,
                    dataHash: hash,
                    dataSize: Int64(attachment.data.count),
                    filename: attachment.filename,
                    mimetype: attachment.contentType
                )
            }) ?? [],
            aiMessage: message.aiMessage,
            humanSupportMessage: message.humanSupportMessage
        )
    }
}
#endif
