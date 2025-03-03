#if os(macOS)
    import SwiftUI

    struct ExternalAboutView: View {
        var body: some View {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 140)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)

                VStack(alignment: .leading, spacing: 5) {
                    Spacer()
                    Text("Roam", comment: "App name")
                        .font(.title)
                        .foregroundStyle(.accent)
                    Spacer()

                    Group {
                        Text("App Version", comment: "Version label in About page for the app") + Text(" ") +
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--")", comment: "Translate directly as \"%@\"")
                    }
                    .font(.headline)
                    Group {
                        Text("Build Version", comment: "Version label in About page for the app") + Text(" ") +
                        Text("\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--")")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()
                    Spacer()

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Made with ❤️ by Scott Driggers", comment: "Text description within the About View for the app")

                        Link(String(localized: "roam-support@msd3.io", comment: "Support email (not localizable)"), destination: URL(string: "mailto:roam-support@msd3.io")!)
                    }
                    .font(.footnote)

                    Spacer()
                }
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

                Spacer()
            }
            .frame(width: 450, height: 200)
        }
    }

    #Preview {
        ExternalAboutView()
    }
#endif
