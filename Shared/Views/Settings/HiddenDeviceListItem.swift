import SwiftUI

struct HiddenDeviceListItem: View {
    let device: Device

#if os(watchOS)
    @EnvironmentObject private var appDelegate: RoamWatchAppDelegate
#else
    @EnvironmentObject private var appDelegate: RoamAppDelegate
#endif

    @State private var deviceError: Error?
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.id)) {
            Group {
                Text(device.name) + Text(" · ") +
                Text(getHostPortDisplay(from: device.location)).foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
        }
#if !os(watchOS)
        .contextMenu {
            Button(role: .destructive) {
                let pid = device.id
                Task {
                    do {
                        try await RoamDataHandler.shared.deleteDevice(id: pid)
                        Log.userInteraction
                            .notice(
                                "Deleted device with id \(String(describing: pid), privacy: .public)"
                            )
                    } catch let error as DataHandlerError {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                        errorMessage = "Failed to Delete Device"
                        deviceError = error
                    }
                }
            } label: {
                Label(String(localized: "Delete", comment: "Label on a button to delete a device"), systemImage: "trash")
            }
            Button {
                let pid = device.id
                Task {
                    do {
                        try await RoamDataHandler.shared.setDeviceHidden(
                            id: pid,
                            hidden: false
                        )
                    } catch {
                        Log.data.warning("Error updating device \(error, privacy: .public)")
                        errorMessage = "Failed to Unhide Device"
                        deviceError = error
                    }
                }
            } label: {
                Label("Unhide", systemImage: "eye")
            }
            NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.id)) {
                Label(String(localized: "Edit", comment: "Label on a button to edit a device"), systemImage: "pencil")
            }
        }
#endif
        .swipeActions(edge: .leading) {
            Button {
                let pid = device.id
                Task {
                    do {
                        try await RoamDataHandler.shared.setDeviceHidden(
                            id: pid,
                            hidden: false
                        )
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
