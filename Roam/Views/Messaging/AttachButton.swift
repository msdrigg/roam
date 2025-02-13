import SwiftUI

struct AttachButton: View {
    let shareDiagnostics: () -> Void
    let sharePhotos: () -> Void
    let loading: Bool
    @State private var pressCounter = 0

    var imageName: String {
        if loading {
            "rays"
        } else {
            "latch.2.case"
        }
    }

    var body: some View {
        Menu {
            Button(action: {
                shareDiagnostics()
                pressCounter += 1
            }, label: {
                Label(String(localized: "Share Diagnostics", comment: "Label on a button"), systemImage: imageName)
            })
            .symbolEffect(.bounce, value: pressCounter)
#if !os(visionOS)
            .sensoryFeedback(.impact, trigger: pressCounter)
#endif
            .symbolEffect(.variableColor, isActive: loading)
            .help(
                loading ? "Sharing diagnostics..." :
                    "Share diagnostics"
            )
        } label: {
            if loading {
#if os(macOS)
                Image(systemName: "rays")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(Color.gray)
#else
                Label(String(localized: "Sending...", comment: "Label on a button to send a message"), systemImage: "rays")
                    .labelStyle(.iconOnly)
#endif
            } else {
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
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundColor(Color.gray)
        .disabled(loading)
        .symbolEffect(.variableColor, isActive: loading)
    }
}

#if DEBUG
#Preview("Send Diagnostics") {
    @Previewable @State var sharingDiagnostics: Bool = false
    AttachButton(
        shareDiagnostics: {
            Task {
                sharingDiagnostics = true
                defer {
                    sharingDiagnostics = false
                }
                
                try? await Task.sleep(duration: 3)
            }
        },
        sharingDiagnostics: sharingDiagnostics
    )
        .padding()
}
#endif
