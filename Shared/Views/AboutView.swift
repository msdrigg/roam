import os
import SwiftUI

struct Dependency: Identifiable {
    let name: String
    let link: String
    let licenseType: String

    var id: String {
        link
    }
}

#if os(watchOS)
    let webpLicenses = [
        // Not Vendored
        Dependency(
            name: "libwebp",
            link: "https://chromium.googlesource.com/webm/libwebp",
            licenseType: "BSD-3-Clause"
        ),
        // Not Vendored
        Dependency(
            name: "libwebp-Xcode",
            link: "https://github.com/SDWebImage/libwebp-Xcode",
            licenseType: "BSD-3-Clause"
        ),
    ]
#endif

let mainLicenses: [Dependency] = [
    // Not Vendored
    Dependency(name: "Opus", link: "https://github.com/xiph/opus/tree/master", licenseType: "BSD-3-Clause"),
    // Not Vendored
    Dependency(name: "Swift-Opus", link: "https://github.com/alta/swift-opus", licenseType: "BSD-3-Clause"),
    // Vendored
    Dependency(name: "Swift-RTP", link: "https://github.com/alta/swift-rtp", licenseType: "MIT"),
    // Vendored
    Dependency(name: "Wrapping HStack", link: "https://github.com/ksemianov/WrappingHStack", licenseType: "MIT"),
    // Vendored
    Dependency(name: "Async Channels", link: "https://github.com/gh123man/Async-Channels", licenseType: "MIT"),
]

#if os(watchOS)
    let LICENSES = mainLicenses + webpLicenses
#else
    let LICENSES = mainLicenses
#endif

struct AboutView: View {
    @ScaledMetric var textSize = 16
    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "App Version", comment: "Version label in about page for the app")) {
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--")")
                }
                .focusable()

                LabeledContent(String(localized: "Build Version", comment: "Version label in about page for the app")) {
                    Text(Bundle.main.infoDictionary?["CURRENT_PROJECT_VERSION"] as? String ?? "--")
                }
                .focusable()

                LabeledContent(String(localized: "Support Page", comment: "Version label in about page for the app")) {
                    Link("https://roam.msd3.io", destination: URL(string: "https://roam.msd3.io")!)
                        .font(.body)
                        .foregroundStyle(.secondary, .secondary)
                        .lineLimit(1)
                }
                .focusable()
            }

            Section(String(localized: "Licenses", comment: "Section heading in an about page")) {
                licenseIterator
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    @ViewBuilder
    var licenseIterator: some View {
        ForEach(LICENSES, id: \.id) { license in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(license.name)
                        .foregroundStyle(.primary, .primary)

                    Spacer()

                    Link(license.link, destination: URL(string: license.link)!)
                        .foregroundStyle(.secondary, .secondary)
                        .truncationMode(.tail)
                        .lineLimit(1, reservesSpace: true)
                        .frame(height: textSize)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(license.licenseType)
                    .font(.body)
                    .foregroundStyle(.secondary, .secondary)
            }
        }
    }
}

#if DEBUG
#Preview(
    "About",
    traits: .fixedLayout(width: 400.0, height: 300.0)
) {
    AboutView()
}
#endif
