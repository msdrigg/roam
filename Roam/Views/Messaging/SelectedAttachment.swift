import SwiftUI
import UniformTypeIdentifiers
#if !os(watchOS)
import QuickLook
#endif

struct SelectedAttachment {
    let attachment: AttachmentUpload?
    let name: String
    let id: String
    let type: UTType
    let failure: String?
    let loading: Bool

    init(attachment: AttachmentUpload?, name: String, type: UTType, failure: String?, loading: Bool, id: String? = nil) {
        self.attachment = attachment
        self.name = name
        self.id = id ?? name
        self.type = type
        self.failure = failure
        self.loading = loading
    }

    func withAttachment(_ attachment: AttachmentUpload) -> Self {
        return Self(
            attachment: attachment,
            name: attachment.filename,
            type: attachment.utType,
            failure: self.failure,
            loading: false,
            id: self.id
        )
    }

    func withError(_ error: AttachmentError) -> Self {
        return Self(
            attachment: self.attachment,
            name: self.name,
            type: self.type,
            failure: error.errorDescription,
            loading: false,
            id: self.id
        )
    }
}

struct AttachmentPreviewView: View {
    let attachment: SelectedAttachment
    let delete: () -> Void
    let scrollToSelf: () -> Void

    @Environment(\.wrongAttempts) var wrongAttempts
    @Environment(\.layoutDirection) var layoutDirection

    @State private var shaking: Bool = false

    var body: some View {
        AttachmentView(attachment: attachment)
#if os(visionOS)
                .background(.gray.opacity(0.5))
#else
                .background(.secondary.opacity(0.3))
#endif
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topTrailing) {
                Button(action: delete) {
                    Label("Delete", systemImage: "xmark.circle.fill")
                        .padding(.all, 2)
                }
                .background(.ultraThickMaterial)
                .clipShape(Circle())
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .labelStyle(.iconOnly)
                .offset(x: layoutDirection == .rightToLeft ? -8 : 8, y: -8)
            }
            .modifier(ShakeEffect(animatableData: shaking ? 1 : 0))
            .onChange(of: wrongAttempts?.attempts ?? 0) {
                if self.attachment.failure != nil || self.attachment.loading {
                    scrollToSelf()
                    withAnimation(Animation.easeInOut(duration: 0.4)) {
                        shaking.toggle()
                    }
                }
            }
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func modifier(_ x: CGFloat) -> CGFloat {
        return 8 * sin(x * 3 * .pi)
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let transform = ProjectionTransform(
            CGAffineTransform(
                translationX: modifier(animatableData),
                y: 0
            )
        )
        return transform
    }
}

struct TimeOverlayModifier: ViewModifier {
    let message: Message?

    func body(content: Content) -> some View {
        if let message, message.shownTime != nil {
            content
                .overlay(alignment: .bottomTrailing) {
                    MessageMetadataOverlay(message: message)
                        .foregroundStyle(Color.white)
                        .background(Capsule().fill(Color.black.opacity(0.3)).blur(radius: 8))
                        .shadow(color: .black, radius: 8)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

struct AttachmentView: View {
    let attachment: SelectedAttachment
    let message: Message?

    @State private var isExporting: Bool = false
    @State private var previewUrl: URL?

    init(attachment: SelectedAttachment, message: Message? = nil) {
        self.attachment = attachment
        self.message = message
    }

    init(attachment: AttachmentUpload, message: Message? = nil) {
        let upload = AttachmentUpload(
            filename: attachment.filename,
            data: attachment.data,
            contentType: attachment.contentType,
            id: attachment.id
        )
        self.attachment = SelectedAttachment(
            attachment: upload,
            name: attachment.filename,
            type: upload.utType,
            failure: nil,
            loading: false
        )
        self.message = message
    }

    init(attachment: Message.SentAttachment, message: Message? = nil) {
        let upload = AttachmentUpload(
            filename: attachment.filename,
            data: attachment.data,
            contentType: attachment.mimetype,
            id: attachment.id
        )
        self.attachment = SelectedAttachment(
            attachment: upload,
            name: attachment.filename,
            type: upload.utType,
            failure: nil,
            loading: false
        )
        self.message = message
    }

    var documentImage: String {
        if attachment.type.conforms(to: UTType.image) {
            return "photo"
        } else if attachment.type.conforms(to: UTType.movie) {
            return "film"
        } else {
            return "document"
        }
    }

    var loadedData: Data? {
        if attachment.loading || attachment.failure != nil {
             return nil
        }
        return attachment.attachment?.data
    }

    var body: some View {
        if let attachmentDocument = attachment.attachment {
            bodyContent
#if !os(watchOS)
#if !os(macOS)
                .contentShape([.contextMenuPreview, .dragPreview], RoundedRectangle(cornerRadius: 15))
#endif
#if !os(visionOS)
                .onTapGesture {
                    do {
                        previewUrl = try attachmentDocument.writeToTemporaryFile()
                        Log.userInteraction.notice("Wrote url to preview url")
                    } catch {
                        Log.userInteraction.notice("Error writing attachment to temp file \(error, privacy: .public)")
                    }
                }
                .quickLookPreview($previewUrl)
#endif
                .contextMenu {
                    Button(action: {
                        isExporting = true
                        Log.userInteraction.notice("Attempting to download \(attachmentDocument.filename, privacy: .public) with type utType \(attachmentDocument.utType, privacy: .public)")
                    }, label: {
                        Label(String(localized: "Save to files", comment: "Label on a button to download an attachment"), systemImage: "square.and.arrow.down")
                    })
#if !os(macOS)
                    if let data = attachment.attachment?.data, let image = UIImage(data: data) {
                        Button(action: {
                            Log.userInteraction.notice("Attempting to save to photos \(attachmentDocument.filename, privacy: .public) with type utType \(attachmentDocument.utType, privacy: .public)")
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        }, label: {
                            Label(String(localized: "Save to photos", comment: "Label on a button to download an attachment"), systemImage: "square.and.arrow.down")
                        })
                    }
#endif
                }
                .fileExporter(
                    isPresented: $isExporting,
                    document: attachmentDocument,
                    contentType: attachmentDocument.utType,
                    defaultFilename: attachmentDocument.filename
                ) { result in
                    switch result {
                    case .success(let url):
                        print("File saved to: \(url)")
                    case .failure(let error):
                        print("Error saving file: \(error.localizedDescription)")
                    }
                }
#endif
        } else {
            bodyContent
        }
    }

    @ViewBuilder
    var bodyContent: some View {
        HStack {
            DataImageInset(data: loadedData, fallback: {
                HStack {
                    DataImage(from: attachment.attachment?.data, fallback: attachment.loading ? "rays" : documentImage)
                        .symbolEffect(.variableColor, isActive: attachment.loading)
#if os(macOS)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
#else
                        .padding(.vertical, 24)
                        .padding(.horizontal, 8)
#endif
                        .foregroundStyle(attachment.failure != nil ? Color.red : .primary)

                    DocumentName(attachment: attachment)
                        .allowsHitTesting(false)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(minWidth: 140)
                .overlay(alignment: .bottomTrailing) {
                    if let message {
                        MessageMetadataOverlay(message: message)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
            }, imageModifier: {
                TimeOverlayModifier(message: message)
            })
        }
        .frame(maxHeight: 100)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

struct DocumentName: View {
    let attachment: SelectedAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Text(attachment.name)
                    .font(.body.bold())
                    .truncationMode(.tail)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .leading)
            }
            VStack(spacing: 0) {
                if let failure = attachment.failure {
                    Text(failure)
                        .lineLimit(2)
                        .frame(maxWidth: 240, alignment: .leading)
                        .foregroundColor(.red)
                        .font(.caption)
                } else if attachment.loading {
                    Text("Loading...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                if let file = attachment.attachment {
                    Text(file.description)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(maxWidth: 240, alignment: .leading)
                }
            }
            Spacer()
        }
    }
}

#if os(visionOS)
    let globalAttachmentSize: CGFloat = 100
#elseif os(iOS)
    let globalAttachmentSize: CGFloat = 80
#else
    let globalAttachmentSize: CGFloat = 60
#endif

struct AttachmentRow: View {
    @Binding var attachments: [SelectedAttachment]
    @ScaledMetric var gridSize: CGFloat = globalAttachmentSize

    var body: some View {
        ScrollViewReader { scrollValue in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(attachments, id: \.id) { attachment in
                        AttachmentPreviewView(
                            attachment: attachment,
                            delete: {
                                attachments = attachments.filter({a in a.id != attachment.id})
                            },
                            scrollToSelf: {
                                withAnimation(.easeInOut) {
                                    scrollValue.scrollTo(attachment.id)
                                }
                            }
                        )
                    }
                }
                .frame(maxHeight: gridSize)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .padding(.top, 16)
            }
            .scrollIndicators(.never)
        }
    }
}

struct DataImageInset<Fallback, IM>: View  where Fallback: View, IM: ViewModifier {
    let data: Data?
    let fallback: () -> Fallback
    let imageModifier: () -> IM

    init(data: Data?, @ViewBuilder fallback: @escaping () -> Fallback, imageModifier: @escaping () -> IM) {
        self.data = data
        self.imageModifier = imageModifier
        self.fallback = fallback
    }

    var image: Image? {
        if let data {
#if os(macOS)
            if let nsImage = NSImage(data: data) {
                return Image(nsImage: nsImage)
            } else {
                return nil
            }
#else
            if let uiImage = UIImage(data: data) {
                return Image(uiImage: uiImage)
            } else {
                return nil
            }
#endif
        } else {
            return nil
        }
    }

    @ViewBuilder
    var body: some View {
        if let image {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(
                    Color.white
                )
                .modifier(imageModifier())
        } else {
            fallback()
        }
    }
}

#if DEBUG
@MainActor
let previewAttachments = [
    SelectedAttachment(
        attachment: nil, name: "a6", type: .pdf,
        failure: "Image too large (10mb max)", loading: false
    ),
    SelectedAttachment(
        attachment:
            AttachmentUpload(
                filename: "a1.png", data: Data(fromAssetImage: "Netflix")!,
                contentType: "image/png", id: UUID().uuidString
            ),
        name: "a1.png", type: .png, failure: nil, loading: false
    ),
    SelectedAttachment(
        attachment: AttachmentUpload(
            filename: "a2.png", data: Data(fromAssetImage: "Hulu")!,
            contentType: "image/png", id: UUID().uuidString
        ),
        name: "a2.png", type: .png, failure: nil, loading: false
    ),
    SelectedAttachment(
        attachment: AttachmentUpload(
            filename: "a3", data: Data(fromAssetImage: "Hulu")!,
            contentType: "image/png", id: UUID().uuidString
        ),
        name: "a3", type: .png, failure: nil, loading: false
    ),
    SelectedAttachment(
        attachment: AttachmentUpload(
            filename: "a4", data: Data(hexString: "001223")!,
            contentType: "image/png", id: UUID().uuidString
        ),
        name: "a1", type: .png, failure: nil, loading: false
    ),
    SelectedAttachment(attachment: nil, name: "a5", type: .pdf, failure: nil, loading: true)
]
#Preview("Attachment Row") {
    @Previewable @State var attachments = previewAttachments
    AttachmentRow(attachments: $attachments)
}

#Preview("Attachment") {
    AttachmentPreviewView(
        attachment: SelectedAttachment(
            attachment: AttachmentUpload(
                filename: "a1", data: Data(fromAssetImage: "Netflix")!,
                contentType: "image/png", id: UUID().uuidString
            ),
            name: "a1", type: .png, failure: nil, loading: false
        ),
        delete: {},
        scrollToSelf: {}
    )
}
#endif
