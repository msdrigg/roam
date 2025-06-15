import SwiftUI

struct HiddenDeviceListItem: View {
    @Bindable var device: Device

    @Environment(\.uuidUpdater) private var updater
    @State private var deviceError: Error?
    @State private var errorMessage: String = ""

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
                Task {
                    do {
                        try await RoamDataHandler().delete(pid)
                        Log.userInteraction
                            .notice(
                                "Deleted device with id \(String(describing: pid), privacy: .public)"
                            )
                        DispatchQueue.main.async {
                            self.updater?.update()
                        }
                    } catch {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                        errorMessage = "Failed to Delete Device"
                        deviceError = error
                    }
                }
            } label: {
                Label(String(localized: "Delete", comment: "Label on a button to delete a device"), systemImage: "trash")
            }
            Button {
                let pid = device.persistentModelID
                Task {
                    do {
                        try await RoamDataHandler().updateDevice(
                            pid,
                            hidden: false
                        )
                        DispatchQueue.main.async {
                            self.updater?.update()
                        }
                    } catch {
                        Log.data.warning("Error updating device \(error, privacy: .public)")
                        errorMessage = "Failed to Unhide Device"
                        deviceError = error
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
                Task {
                    do {
                        try await RoamDataHandler().updateDevice(
                            pid,
                            hidden: false
                        )
                        DispatchQueue.main.async {
                            self.updater?.update()
                        }
                    } catch {
                        Log.data.warning("Error updating device \(error, privacy: .public)")
                        errorMessage = "Failed to Unhide Device"
                        deviceError = error
                    }
                }
            } label: {
                Label("Unhide", systemImage: "eye")
            }
        }
        .alertingError(message: errorMessage, error: $deviceError)
    }
}
