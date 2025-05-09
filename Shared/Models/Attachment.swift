import UniformTypeIdentifiers
import CoreTransferable
import Foundation
import SwiftUI

public struct AttachmentUpload: Codable, Sendable, Hashable {
    let filename: String
    let dataHash: String
    let dataSize: Int64
    let contentType: String
    let id: String

    let pairedMessages: [String]

    init(filename: String, dataHash: String, dataSize: Int64, contentType: String, id: String, pairedMessages: [String] = []) {
        self.filename = filename
        self.dataHash = dataHash
        self.contentType = contentType
        self.pairedMessages = pairedMessages
        self.id = id
        self.dataSize = dataSize
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
        return style.format(dataSize)
    }

    private var filenameExtension: String {
        (filename as NSString).pathExtension
    }

    public var dataURL: URL? {
        // Get the group container directory
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mainAppGroup) else {
            Log.data.error("Unable to get group container URL")
            return nil
        }

        return containerURL
            .appendingPathComponent("message-attachments", isDirectory: true)
            .appendingPathComponent(dataHash, isDirectory: true)
            .appendingPathComponent(filename)
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

#if !os(watchOS)
extension AttachmentUpload: FileDocument {
    public init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let hash = fastHashData(data: fileData)
        let filename = "Unknown" // No way to get filename from FileDocument
        try storeAttachmentToDisk(attachmentData: fileData, hash: hash, filename: filename)

        self.filename = filename
        self.dataSize = Int64(fileData.count)
        self.dataHash = hash
        self.contentType = configuration.contentType.preferredMIMEType ?? "application/octet-stream"
        self.id = UUID().uuidString
        self.pairedMessages = []
    }

    public static let readableContentTypes: [UTType] = [.data, .pdf, .png, .image, .jpeg, .json, .text, .movie, .archive]

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let dataURL else {
            throw AttachmentError.loadingFailed
        }
        return try FileWrapper(url: dataURL)
    }
}
#endif

extension AttachmentUpload: Transferable {
    // MARK: - Transferable Conformance
    public typealias Representation = FileRepresentation<AttachmentUpload>
    static public var transferRepresentation: FileRepresentation<AttachmentUpload> {
        FileRepresentation(exportedContentType: UTType.data, shouldAllowToOpenInPlace: true) { (attachment: AttachmentUpload) in
            guard let dataURL = attachment.dataURL else {
                throw AttachmentError.loadingFailed
            }
            return SentTransferredFile(dataURL)
        }
    }
}
