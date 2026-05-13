#if !os(watchOS)
import SwiftUI

/// Attaches the standard Edit + Delete actions to a device row or card.
///
/// On touch platforms the actions are exposed via `.swipeActions` so the user
/// can swipe-from-trailing on a sidebar card to reveal them. On every platform
/// (incl. macOS) the same actions are available via right-click / long-press
/// `.contextMenu`. Delete shows a confirmation dialog before calling
/// `RoamDataHandler.deleteDevice(id:)`.
struct DeviceActionsModifier: ViewModifier {
    let deviceId: String
    let deviceName: String?
    let onEdit: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var deviceError: Error?

    func body(content: Content) -> some View {
        content
        #if !os(macOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(
                        String(localized: "Delete", comment: "Swipe action to delete a device"),
                        systemImage: "trash"
                    )
                }

                Button {
                    onEdit()
                } label: {
                    Label(
                        String(localized: "Edit", comment: "Swipe action to edit a device"),
                        systemImage: "pencil"
                    )
                }
                .tint(.blue)
            }
        #endif
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label(
                        String(localized: "Edit", comment: "Context-menu action to edit a device"),
                        systemImage: "pencil"
                    )
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(
                        String(localized: "Delete", comment: "Context-menu action to delete a device"),
                        systemImage: "trash"
                    )
                }
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    String(localized: "Delete", comment: "Confirm button for deleting a device"),
                    role: .destructive
                ) {
                    performDelete()
                }
                Button(
                    String(localized: "Cancel", comment: "Cancel button for the delete-device dialog"),
                    role: .cancel
                ) {}
            } message: {
                Text(
                    "This will remove the device from Roam. You can always add it back later.",
                    comment: "Body text of the device delete confirmation dialog"
                )
            }
            .alertingError(message: "Failed to Delete Device", error: $deviceError)
    }

    private var deleteConfirmationTitle: String {
        if let name = deviceName, !name.isEmpty {
            return String(
                format: String(
                    localized: "Delete “%@”?",
                    comment: "Title of the device delete confirmation dialog with the device name interpolated"
                ),
                name
            )
        }
        return String(
            localized: "Delete device?",
            comment: "Generic title of the device delete confirmation dialog when the device name is unknown"
        )
    }

    private func performDelete() {
        let id = deviceId
        Task {
            do {
                try await RoamDataHandler.shared.deleteDevice(id: id)
                Log.userInteraction.notice(
                    "Deleted device with id \(String(describing: id), privacy: .public) from sidebar action"
                )
            } catch let error as DataHandlerError {
                Log.userInteraction.error(
                    "Error deleting device \(error, privacy: .public)")
                deviceError = error
            } catch {
                Log.userInteraction.error(
                    "Error deleting device \(error, privacy: .public)")
                deviceError = error
            }
        }
    }
}

extension View {
    func deviceActions(
        deviceId: String,
        deviceName: String?,
        onEdit: @escaping () -> Void
    ) -> some View {
        modifier(DeviceActionsModifier(deviceId: deviceId, deviceName: deviceName, onEdit: onEdit))
    }
}
#endif
