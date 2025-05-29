import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
                        selectedPhotos = []
                    }
                }
        }
    }

    var bodyContent: some View {
        Menu {
            Button(action: {
                handleAttachment(DiagnosticsImport(userInitiated: true))
                diagnosticsPressCounter += 1
            }, label: {
                Label(String(localized: "Attach Diagnostics", comment: "Label on a button"), systemImage: "latch.2.case")
            })
            .symbolEffect(.bounce, value: diagnosticsPressCounter)
#if !os(visionOS)
            .sensoryFeedback(.impact, trigger: diagnosticsPressCounter)
#endif
            .labelStyle(.titleAndIcon)

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
        .fileImporter(
            isPresented: $pickingFiles,
            allowedContentTypes: [UTType.image, UTType.json, UTType.text, UTType.pdf, UTType.movie, .archive],
            allowsMultipleSelection: false,
            onCompletion: { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        Log.userInteraction.warning("Got 0 items from file importer")
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
            maxSelectionCount: 1
        )
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
