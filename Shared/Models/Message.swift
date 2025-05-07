import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

public typealias Message = SchemaV4.Message

extension Message {
    var timestamp: Date? {
        return parseDiscordSnowflake(self.id)
    }

    func cycleAttachments(_ attachments: [SentAttachment]) {
        let encoder = PropertyListEncoder()
        self.attachmentsData = try? encoder.encode(attachments)
        self.unsentAttachmentData = nil
    }

    internal static func fetchAllRequest() -> FetchDescriptor<Message> {
        var fd = FetchDescriptor(
            predicate: #Predicate<Message> { _ in
                true
            }
        )
        fd.relationshipKeyPathsForPrefetching = []

        return fd
    }

    func triggerAction() {
#if !WIDGET
        if self.message.hasPrefix(":command-share-diagnostics:") {
            Task {
                do {
                    let upload = try await DiagnosticsImport().load().get()
                    try await DataHandler().sendChatMessage(message: ":ninja:", attachments: [upload])
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
            attachments: message.attachments?.map({ attachment in
                return Message.SentAttachment(
                    id: attachment.id,
                    data: attachment.data,
                    filename: attachment.filename,
                    mimetype: attachment.contentType
                )
            }) ?? []
        )
    }
}
#endif

public struct AttachmentUpload: Codable, Sendable, Hashable {
    let filename: String
    let data: Data
    let contentType: String
    let id: String

    let pairedMessages: [String]

    init(filename: String, data: Data, contentType: String, id: String, pairedMessages: [String] = []) {
        self.filename = filename
        self.data = data
        self.contentType = contentType
        self.pairedMessages = pairedMessages
        self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case filename = "filename"
        case data = "data"
        case contentType = "content_type"
        case pairedMessages = "paired_messages"
        case id = "id"
    }

    var description: String {
        let type = utType

        return [type.localizedDescription ?? "Document", bytesString].joined(separator: " · ")
    }

    var bytesString: String {
        let style = ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.kb, .mb],
            spellsOutZero: true,
            includesActualByteCount: false,
            locale: Locale.current
        )
        return style.format(Int64(data.count))
    }

    private var filenameExtension: String {
        (filename as NSString).pathExtension
    }

    var utType: UTType {
        let rewrites = [
            "application/pdf": UTType.pdf
        ]
        if let type = rewrites[self.contentType] {
            return type
        }
        if let type = UTType(tag: self.contentType, tagClass: .mimeType, conformingTo: nil), type.isPublic {
            return type
        }
        if let type = UTType(tag: self.filenameExtension, tagClass: .filenameExtension, conformingTo: nil), type.isPublic {
            return type
        }

        return .data
    }
}
