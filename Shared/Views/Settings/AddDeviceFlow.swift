import SwiftUI

struct AddDeviceFlow: View {
    @State var ipAddress: String = ""
    @State var globalError: String?
    @State var ipAddressError: String?

    var body: some View {
        Form {
            Text("Add Device")
            TextField("IP Address", text: $ipAddress)
        }
        .formStyle(.grouped)
        .onSubmit {
            <#code#>
        }
    }
    
    func submit() {
        Task {
            let modelContainer = getSharedModelContainer()
            let dataHandler = DataHandler(modelContainer: modelContainer)
            let location = "http://\(ipAddress):8060/"
            do {
                let preConnectInfo = try await fetchPreconnectionInfo(location: ipAddress)
                await dataHandler.addDeviceIndistriminantly(
                    location: location,
                    friendlyDeviceName: preConnectInfo.friendlyName,
                    udn: preConnectInfo.udn,
                    serial: preConnectInfo.serial,
                    hidden: false
                )
            } catch {
                self.globalError = error.localizedDescription
            }
        }
    }
}

// TODO: 1. Make it auto-connect to devices as you type but bail out once the IP address fails
// TODO: 2. If possible, restrict to numbers + dot but allow switching keyboards if the user wants to. If not possible, don't worry about it
// TODO: 3. Show example of IP address + more instructions on how to find it on the TV
// TODO: 4. Show <Connecting indicator> before failure
// TODO: 5. Show failure if it fails.
// TODO: 6. If it's green, mark it as selected and close indicator
// TODO: 7. Make it look pretty on vision, mac, ios, ipad and watchOS
