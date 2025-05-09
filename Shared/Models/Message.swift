import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

public typealias Message = SchemaV5.Message

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
        if self.message.hasPrefix(":command-share-diagnostics:") {
            Task {
                do {
                    let upload = try await DiagnosticsImport().load().get()
                    try await DataHandler().sendChatMessage(message: ":ninja:", attachment: upload)
                    Log.backend.notice("Sent attachment to share diagnostics \(String(describing: upload), privacy: .public)")
                } catch {
                    Log.backend.warning("Error sending diagnostics on command-share: \(error, privacy: .public)")
                }
            }
        }
#endif
    }

    func expandMessage() -> String {
        let replacements: [String: String] = [
            ":manually-add-tv:": String(
                localized: ":manually-add-tv:",
                defaultValue: "You can find the instructions for how to manually add a TV here: https://roam.msd3.io/manually-add-tv/",
                comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
            ),
            ":manually-add-tv-full:": String(
                localized: ":manually-add-tv-full:",
                // swiftlint:disable:next line_length
                defaultValue: "Hi, it sounds like you are having trouble connecting to your Roku TV. If the Roam app isn't automatically detecting your TV, you can manually add it by following the instructions here: https://roam.msd3.io/manually-add-tv/",
                comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
            ),
            ":help-share-diagnostics:": String(
                localized: ":help-share-diagnostics:",
                defaultValue: "To share diagnostics, click the plus button at the bottom of the chat window and then click \"Attach diagnostics\"",
                comment: "Help text. Note that the URL can be localized with https://roam.msd3.io/<lang>/manually-add-tv/"
            ),
            ":message-from-roam-title:": String(
                localized: ":message-from-roam-title:",
                defaultValue: "Message from Roam",
                comment: "Localize as 'Message from Roam'"
            )
        ]

        var expandedMessage = self.message

        for (key, value) in replacements {
            expandedMessage = expandedMessage.replacingOccurrences(of: key, with: value)
        }

        return expandedMessage
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
