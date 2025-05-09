import SwiftUI

struct WatchOSNote: View {
    var body: some View {
        Form {
            Section("Permissive Mode") {
                Text(
                    // swiftlint:disable:next line_length
                    "Due to WatchOS limitations, you may need to enable \"Permissive\" Network Access on your Roku TV. You can do this by going to **Settings > System > Advanced system settings > Control by mobile apps > Network**",
                    comment: "WatchOS indicator showing that watchOS can't auto-discover TV's due to network restrictions"
                )
            }

            Section("Manually Adding TVs") {
                Text(
                    "Additinoally, WatchOS prevents us from discovering TV's on the local network.",
                    comment: "WatchOS indicator showing that watchOS can't auto-discover TV's due to network restrictions"
                )

                Text(
                    // swiftlint:disable:next line_length
                    "To work around this limitation, first discover devices on the iPhone app and then the devices will be transferred in the background from the iPhone to the watch (or you can manually add the TV if you can get it's IP address).",
                    comment: "Description of watchOS discovery alternatives"
                )
            }

            Section("Getting in Touch") {
                Text(
                    // swiftlint:disable:next line_length
                    "Please be patient, because I don't have an apple watch so I can't test how effective this is. Please reach out if you aren't able to get this to work :). You message me by clicking \"Chat with developer\" from Roam settings",
                    comment: "Description of watchOS discovery alternatives"
                )
            }
        }
    }
}

#Preview(
    "WatchOS Note"
) {
    WatchOSNote()
}
