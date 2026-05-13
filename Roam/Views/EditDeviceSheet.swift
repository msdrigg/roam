#if !os(watchOS)
import SwiftUI

/// Thin sheet wrapper around `DeviceDetailView`. Provides the toolbar Done
/// button that the underlying form does not, and routes the form's own
/// `dismiss` callback (used after a successful delete) back to the binding so
/// the sheet closes from either path.
struct EditDeviceSheet: View {
    @Binding var deviceIdToEdit: String?

    var body: some View {
        if let deviceId = deviceIdToEdit {
            NavigationStack {
                DeviceDetailView(deviceId: deviceId) {
                    deviceIdToEdit = nil
                }
                .navigationTitle(String(
                    localized: "Edit Device",
                    comment: "Title of the sheet for editing a device's settings"
                ))
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(
                            localized: "Done",
                            comment: "Button to dismiss the edit device sheet"
                        )) {
                            deviceIdToEdit = nil
                        }
                    }
                }
            }
        }
    }
}
#endif
