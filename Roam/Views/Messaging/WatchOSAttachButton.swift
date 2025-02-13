import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum AttachmentError: Error, LocalizedError {
    case fileTooLarge(Int)
    case unsupportedFileType(UTType)
    case loadingFailed
    case cancelled
    case failedToEncode
    
    var errorDescription: String {
        switch self {
        case .fileTooLarge(let size):
            return String(localized: "File too large (over \(size) bytes)")
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

struct DiagnosticsImport: PendingAttachment {
    let utType: UTType = .json
    let id: String

    var filename: String {
        "Diagnostics.json"
    }

    init() {
        id = "diagnostics-\(UUID().uuidString)"
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        let loggingAt = Date.now
        Log.userInteraction.notice("Starting to send logs \(loggingAt, privacy: .public)")
        let logs = await getDebugInfo(container: getSharedModelContainer())
        Log.userInteraction.notice("Sending logs \(logs.installationInfo.userId, privacy: .public)")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(logs)
            
            return .success(AttachmentUpload(filename: self.filename, data: data, contentType: "application/json", id: self.id, pairedMessages: [getDebugLogMessageString(logs)]))
        } catch {
            return .failure(.failedToEncode)
        }
    }
}

#if !os(watchOS)
struct ItemProviderAttachment: PendingAttachment {
    let filename: String
    let utType: UTType
    let id: String
    let provider: ItemProvider
    
    init?(_ provider: ItemProvider, name: String) {
        guard let contentType = provider.registeredContentTypes.first else {
            Log.userInteraction.warning("Unsupported file type for \(provider, privacy: .public)")
            return nil
        }
        self.utType = contentType
        self.filename = rewriteName(contentType, provider.suggestedName ?? name)

        id = "ItemProvider-\(UUID().uuidString)"
        self.provider = provider
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<AttachmentUpload, AttachmentError>, Never>) in
            Log.userInteraction.notice("Loading attachment for type \(utType, privacy: .public)")
            _ = provider.loadDataRepresentation(for: utType) { data, error in
                if let error {
                    Log.userInteraction.error("Error loading data for uttype (\(utType, privacy: .public)):  \(error, privacy: .public)")
                }
                guard let data else {
                    continuation.resume(returning: Result.failure(AttachmentError.loadingFailed))
                    return
                }

                continuation.resume(returning: .success(AttachmentUpload(filename: filename, data: data, contentType: utType.preferredMIMEType ?? "application/octet-stream", id: self.id)))
            }
        }
    }
}

struct FileImport: PendingAttachment {
    let url: URL
    let filename: String
    let utType: UTType
    let id: String

    init?(url: URL) {
        self.url = url
        self.id = url.absoluteString

        // Get file type (UTType)
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            Log.userInteraction.notice("Error loading file from url\(url, privacy: .public)")
            return nil
        }
        self.filename = rewriteName(type, url.lastPathComponent)
        self.utType = type
    }
    
    func load() async -> Result<AttachmentUpload, AttachmentError> {
        do {
#if os(macOS)
            guard url.startAccessingSecurityScopedResource() else {
                return .failure(.loadingFailed)
            }
            defer { url.stopAccessingSecurityScopedResource() }
#endif
            // Read file data asynchronously for local files
            // Handle remote URLs
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let filename = url.lastPathComponent
            
            return .success(AttachmentUpload(filename: filename, data: data, contentType: utType.preferredMIMEType ?? "application/octet-stream", id: self.id))
        } catch {
            return .failure(.loadingFailed)
        }
    }
}
#endif

struct PhotoImport: PendingAttachment {
    let item: PhotosPickerItem
    let filename: String
    let utType: UTType
    let id: String

    init?(item: PhotosPickerItem) {
        self.item = item
        self.id = UUID().uuidString

        if let itemType = item.supportedContentTypes.first {
            self.utType = itemType
        } else {
            return nil
        }

        self.filename = "photo.png"
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return .failure(.loadingFailed)
            }

#if os(macOS)
            if let image = NSImage(data: data), let pngData = image.pngData() {
                return .success(AttachmentUpload(
                    filename: "photo.png",
                    data: pngData,
                    contentType: "image/png",
                    id: self.id
                ))
            }
#else
            if let image = UIImage(data: data), let pngData = image.pngData() {
                return .success(AttachmentUpload(
                    filename: "photo.png",
                    data: pngData,
                    contentType: "image/png",
                    id: self.id
                ))
            }
#endif

            return .success(AttachmentUpload(
                filename: filename,
                data: data,
                contentType: utType.preferredMIMEType ?? "application/octet-stream",
                id: self.id
            ))

        } catch {
            return .failure(.loadingFailed)
        }
    }
}

func rewriteName(_ utType: UTType, _ filename: String) -> String {
    if let preferredExtension = utType.preferredFilenameExtension {
        let baseName = (filename as NSString).deletingPathExtension
        return "\(baseName).\(preferredExtension)"
    } else {
        return filename
    }
}

struct AttachButton: View {
    let handleAttachment: (any PendingAttachment) -> Void

    @State var selectedPhotos: [PhotosPickerItem] = []
    @State var pickingPhotos: Bool = false
    @State private var photosPressCounter = 0

    @State var pickingFiles: Bool = false
    @State private var filePressCounter = 0

    @State private var diagnosticsPressCounter = 0

    var body: some View {
        if runningInPreview {
            bodyContent
        } else {
            bodyContent
            #if !os(watchOS)
                .onChange(of: selectedPhotos) {
                    if selectedPhotos.count > 0 {
                        for photo in selectedPhotos {
                            if let attachment = PhotoImport(item: photo) {
                                Log.userInteraction.notice("Got import for photo \(photo.itemIdentifier ?? "nil", privacy: .public)")
                                handleAttachment(attachment)
                            } else {
                                Log.userInteraction.notice("Unable to create photo import for photo \(photo.itemIdentifier ?? "nil", privacy: .public)")
                            }
                        }
                    }
                }
            #endif
        }
    }

    var bodyContent: some View {
        Menu {
            Button(action: {
                handleAttachment(DiagnosticsImport())
                diagnosticsPressCounter += 1
            }, label: {
                Label(String(localized: "Attach Diagnostics", comment: "Label on a button"), systemImage: "latch.2.case")
            })
            .symbolEffect(.bounce, value: diagnosticsPressCounter)
#if !os(visionOS)
            .sensoryFeedback(.impact, trigger: diagnosticsPressCounter)
#endif
            .labelStyle(.titleAndIcon)
            
#if !os(watchOS)
            Button(action: {
                pickingFiles = true
                filePressCounter += 1
            }, label: {
                Label(String(localized: "Attach files", comment: "Label on a button"), systemImage: "document.badge.plus")
            })
            .symbolEffect(.bounce, value: filePressCounter)
#if !os(visionOS)
            .sensoryFeedback(.impact, trigger: filePressCounter)
#endif
            .labelStyle(.titleAndIcon)

            Button(action: {
                pickingPhotos = true
                photosPressCounter += 1
            }, label: {
                Label(String(localized: "Attach photos", comment: "Label on a button"), systemImage: "photo.badge.plus")
            })
            .symbolEffect(.bounce, value: photosPressCounter)
#if !os(visionOS)
            .sensoryFeedback(.impact, trigger: photosPressCounter)
#endif
            .labelStyle(.titleAndIcon)
#endif
        } label: {
            Label {
                Text("Add Attachment")
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .resizable()
#if os(macOS)
                    .frame(width: 20, height: 20)
#else
                    .frame(width: 26, height: 26)
#endif
                    .foregroundColor(Color.gray)
            }
            .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundColor(Color.gray)
#if !os(watchOS)
        .fileImporter(
            isPresented: $pickingFiles,
            allowedContentTypes: [UTType.image, UTType.json, UTType.plainText, UTType.pdf, UTType.movie],
            allowsMultipleSelection: false,
            onCompletion: { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        Log.userInteraction.warning("Got \(0, privacy: .public) items from file importer")
                        return
                    }
                    Log.userInteraction.notice("Got \(urls, privacy: .public) items from file importer")
                    if let attachment = FileImport(url: url) {
                        handleAttachment(attachment)
                    } else {
                        Log.userInteraction.notice("Unable to import url \(url, privacy: .public) items from file importer")
                    }
                case .failure:
                    break
                }
            }
        )
        .photosPicker(
            isPresented: $pickingPhotos,
            selection: $selectedPhotos,
            maxSelectionCount: 3
        )
#endif
    }
}

#if DEBUG
#Preview("Send Diagnostics") {
    AttachButton(
        handleAttachment: { attachment in
            Log.userInteraction.notice("Sending \(String(describing: attachment))")
        }
    )
        .padding()
}
#endif
