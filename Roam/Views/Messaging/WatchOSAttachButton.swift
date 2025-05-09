import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AttachButton: View {
    let handleAttachment: (any PendingAttachment) -> Void

    @State var showingSheet: Bool = false

    @State private var diagnosticsPressCounter = 0

    var body: some View {
        Button(action: {showingSheet = true}, label: {
            Label {
                Text("Add Attachment")
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .foregroundColor(Color.gray)
            }
            .labelStyle(.iconOnly)
        })
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            NavigationStack {
                List {
                    Button(action: {
                        handleAttachment(DiagnosticsImport())
                        diagnosticsPressCounter += 1
                        showingSheet = false
                    }, label: {
                        Label(String(localized: "Attach Diagnostics", comment: "Label on a button"), systemImage: "latch.2.case")
                    })
                    .symbolEffect(.bounce, value: diagnosticsPressCounter)
                    .sensoryFeedback(.impact, trigger: diagnosticsPressCounter)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Send Diagnostics") {
    AttachButton(
        handleAttachment: { attachment in
            Log.userInteraction.notice("Sending \(String(describing: attachment))")
        }
    ).padding()
}
#endif
