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
    /// How many times this message has been handed to the backend and not
    /// landed. Persisted, because giving up has to survive a relaunch: an
    /// in-memory count means a message the backend will never accept starts
    /// over on every launch and retries forever.
    var sendAttemptCount: Int = 0
    var nonce: String?
    var sentAttachments: [SentAttachment]
    var unsentAttachment: AttachmentUpload?
    var messageTitle: String?
    var robotMessage: Bool = false
    var aiMessage: Bool = false
    var humanSupportMessage: Bool = false

    /// How many failed attempts before the app stops trying on its own.
    ///
    /// With the backoff below this is roughly two and a half hours of trying,
    /// which comfortably covers a flaky connection or a backend restart. Past
    /// it, the message is almost certainly one the backend will never accept -
    /// a body it rejects, an attachment it refuses - and retrying forever costs
    /// the user's battery and data to no end. At that point it is better to say
    /// so and let them decide.
    static let maxSendAttempts = 10

    /// Whether the app has stopped retrying this message and is waiting on the
    /// user.
    var sendFailed: Bool {
        !fetchedBackend && sendAttemptCount >= Self.maxSendAttempts
    }

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
    /// Id of the message shown after the developer unlock code is redeemed. It
    /// is synthesized on device and never round-trips to the backend, so - like
    /// `"start"` - it is not a snowflake and carries no timestamp.
    static let developerUnlockID = "developer-unlock"

    /// Messages the app makes up locally. They have no backend copy, so they
    /// must never render a send indicator or a parsed-from-id timestamp.
    var isLocallyGenerated: Bool {
        robotMessage || id == "start" || id == Self.developerUnlockID
    }

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
    /// `localAttachment` is the copy the sender already holds on disk.
    ///
    /// The send response no longer echoes attachment bytes back: the backend
    /// was re-fetching an 8MB diagnostics file off Discord's CDN and base64ing
    /// it into an 11MB response, for bytes the device had just uploaded from
    /// its own disk. An attachment that arrives with no data is matched to that
    /// local copy instead, so the message keeps a usable `dataHash` rather than
    /// being written out as an empty file. Polled messages still carry data and
    /// take the path below.
    init(_ message: MessageModelResponse, localAttachment: AttachmentUpload? = nil) {
        self.init(
            id: message.id,
            message: message.message,
            author: message.author,
            attachments: message.attachments?.compactMap({ attachment in
                if attachment.data.isEmpty {
                    guard let localAttachment else { return nil }
                    return Message.SentAttachment(
                        id: attachment.id,
                        dataHash: localAttachment.dataHash,
                        dataSize: localAttachment.dataSize,
                        filename: localAttachment.filename,
                        mimetype: localAttachment.contentType
                    )
                }
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
