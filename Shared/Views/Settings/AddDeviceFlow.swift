import SwiftUI

struct AddDeviceFlow: View {
    var ipAddress: Binding<String>

    var body: some View {
        Form {
            Text("Add Device")
            TextField("IP Address", text: $ipAddress)
        }
        .formStyle(.grouped)
    }
}
