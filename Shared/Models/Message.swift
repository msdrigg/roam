import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

public typealias Message = SchemaV5.Message

let globalUnviewedMessagePredicate = #Predicate<Message> {
    !$0.viewed
}

extension Message {
    var timestamp: Date? {
        return parseDiscordSnowflake(self.id)
    }

    func cycleAttachments(_ attachments: [Message.SentAttachment]) {
        let encoder = PropertyListEncoder()
        self.attachmentsDataV2 = try? encoder.encode(attachments)
        self.unsentAttachmentDataV2 = nil
    }

    func triggerAction() {
#if !WIDGET
        if self.message.hasPrefix(":command-share-diagnostics:") || self.message.hasPrefix(":command_share_diagnostics:") {
            Task {
                do {
                    let upload = try await DiagnosticsImport(userInitiated: false).load().get()
                    try await MessageDataHandler.shared.sendChatMessage(message: ":ninja:", attachment: upload)
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

@available(*, unavailable)
extension Message: Sendable {}

#if !WIDGET
extension Message {
    convenience init(_ message: MessageModelResponse) {
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
            }) ?? []
        )
    }
}
#endif
