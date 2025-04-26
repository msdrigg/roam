import UniformTypeIdentifiers

enum AttachmentError: Error {
    case fileTooLarge(Int)
    case unsupportedFileType(UTType)
    case loadingFailed
    case cancelled
    case failedToEncode

    var errorDescription: String {
        switch self {
        case .fileTooLarge(_):
            let style = ByteCountFormatStyle(
                style: .file,
                allowedUnits: [.kb, .mb],
                spellsOutZero: true,
                includesActualByteCount: false,
                locale: Locale.current
            )
//            let sizeString = style.format(Int64(size))
            let maxSizeString = style.format(Int64(1000000 * 10))
            return String(localized: "Max upload size \(maxSizeString)")
        case .cancelled:
            return String(localized: "Attachment upload cancelled")
        case .loadingFailed:
            return String(localized: "Failed to load attachment")
        case .unsupportedFileType(let uti):
            return String(localized: "Unsupported file type: \(uti.localizedDescription ?? String(localized: "Unknown"))")
        case .failedToEncode:
            return String(localized: "Failed to encode attachment data")
        }
    }
}

@MainActor
protocol PendingAttachment: Identifiable {
    var utType: UTType { get }
    var filename: String { get }
    var id: String { get }

    func load() async -> Result<AttachmentUpload, AttachmentError>
}
