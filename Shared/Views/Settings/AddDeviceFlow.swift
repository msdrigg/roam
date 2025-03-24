import SwiftUI

struct AddDeviceFlow: View {
//    var ipAddress: Binding<String>
    @State
    var ipAddress: String = ""

    var body: some View {
        Form {
            Text("Add Device")
            TextField("IP Address", text: $ipAddress)
        }
        .formStyle(.grouped)
    }
}
