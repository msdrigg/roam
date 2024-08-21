import os
import SwiftData
import SwiftUI

struct Dependency: Identifiable {
    let name: String
    let link: String
    let licenseType: String

    var id: String {
        link
    }
}

#if os(watchOS) || os(tvOS)
    let webpLicenses = [
        Dependency(
            name: "libwebp",
            link: "https://chromium.googlesource.com/webm/libwebp",
            licenseType: "BSD-3-Clause"
        ),
        Dependency(
            name: "libwebp-Xcode",
            link: "https://github.com/SDWebImage/libwebp-Xcode",
            licenseType: "BSD-3-Clause"
        ),
    ]
#endif

#if os(macOS)
    let macosLicenses = [
        Dependency(name: "SettingsAccess", link: "https://github.com/orchetect/SettingsAccess", licenseType: "MIT"),
    ]
#endif

let mainLicenses: [Dependency] = [
    Dependency(name: "Opus", link: "https://github.com/xiph/opus/tree/master", licenseType: "BSD-3-Clause"),
    Dependency(name: "Swift-Opus", link: "https://github.com/alta/swift-opus", licenseType: "BSD-3-Clause"),
    Dependency(name: "Swift-RTP", link: "https://github.com/alta/swift-rtp", licenseType: "MIT"),
    Dependency(
        name: "Swift-Async-Algorithms",
        link: "https://github.com/apple/swift-async-algorithms",
        licenseType: "Apache-2.0"
    ),
    Dependency(name: "SSDPClient", link: "https://github.com/pierrickrouxel/SSDPClient", licenseType: "MIT"),
    Dependency(name: "XMLCoder", link: "https://github.com/CoreOffice/XMLCoder", licenseType: "MIT"),
    Dependency(name: "AsyncSemaphore", link: "https://github.com/groue/Semaphore", licenseType: "MIT"),
    Dependency(
        name: "Swift Collections",
        link: "https://github.com/apple/swift-collections",
        licenseType: "Apache-2.0"
    ),
    Dependency(name: "Wrapping HStack", link: "https://github.com/ksemianov/WrappingHStack", licenseType: "MIT"),
]

#if os(watchOS) || os(tvOS)
    let LICENSES = mainLicenses + webpLicenses
#elseif os(macOS)
    let LICENSES = mainLicenses + macosLicenses
#else
    let LICENSES = mainLicenses
#endif

struct AboutView: View {
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
        ForEach(Array(zip(LICENSES.indices, LICENSES)), id: \.0) { idx, license in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if idx % 8 == 7 {
                        Text(license.name)
                            .foregroundStyle(.primary, .primary)
                        #if os(tvOS)
                            .focusable()
                        #endif
                    } else {
                        Text(license.name)
                            .foregroundStyle(.primary, .primary)
                    }

                    Spacer()

                    #if os(tvOS)
                        Text(license.link)
                            .font(.body)
                            .foregroundStyle(.secondary, .secondary)
                            .lineLimit(1)
                    #else
                        Link(license.link, destination: URL(string: license.link)!)
                            .font(.body)
                            .foregroundStyle(.secondary, .secondary)
                            .lineLimit(1)
                    #endif
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
    traits: .fixedLayout(width: 100.0, height: 300.0)
) {
    AboutView()
        .modelContainer(previewContainer)
}
#endif
