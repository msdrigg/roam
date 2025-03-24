import SwiftUI

struct HiddenDeviceListItem: View {
    @Bindable var device: Device

    @Environment(\.uuidUpdater) private var updater

    var body: some View {
        NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.persistentModelID)) {
            Group {
                Text(device.name) + Text(" · ") +
                Text(getHostPortDisplay(from: device.location)).foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
        }
#if !os(watchOS)
        .contextMenu {
            Button(role: .destructive) {
                let pid = device.persistentModelID
                Task.detached {
                    do {
                        try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                        Log.userInteraction
                            .notice(
                                "Deleted device with id \(String(describing: pid), privacy: .public)"
                            )
                        DispatchQueue.main.async {
                            self.updater?.update()
                        }
                    } catch {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                    }
                }
            } label: {
                Label(String(localized: "Delete", comment: "Label on a button to delete a device"), systemImage: "trash")
            }
            Button {
                let pid = device.persistentModelID
                Task.detached {
                    await DataHandler(modelContainer: getSharedModelContainer()).updateDevice(
                        pid,
                        hidden: false
                    )
                    DispatchQueue.main.async {
                        self.updater?.update()
                    }
                }
            } label: {
                Label("Unhide", systemImage: "eye")
            }
            NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.persistentModelID)) {
                Label(String(localized: "Edit", comment: "Label on a button to edit a device"), systemImage: "pencil")
            }
        }
#endif
        .swipeActions(edge: .leading) {
            Button {
                let pid = device.persistentModelID
                Task.detached {
                    await DataHandler(modelContainer: getSharedModelContainer()).updateDevice(
                        pid,
                        hidden: false
                    )
                    DispatchQueue.main.async {
                        self.updater?.update()
                    }
                }
            } label: {
                Label("Unhide", systemImage: "eye")
            }
        }
    }
}
