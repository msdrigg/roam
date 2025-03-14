import SwiftUI
import SwiftData

struct DeviceDetailView: View {
    @State private var scanningActor: DeviceDiscoveryActor!

    var deviceId: PersistentIdentifier
    @State var deviceName: String = getGlobalNewDeviceName()
    @State var deviceIP: String = "192.168.0.1"
    @State var hidden: Bool = false

    @State var showHeadphonesModeDescription: Bool = false

    @Query private var selectedDevices: [Device]
    @Environment(\.uuidUpdater) private var updater

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @MainActor
    init(deviceId: PersistentIdentifier, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        self.deviceId = deviceId
        var descriptor = FetchDescriptor<Device>(predicate: #Predicate<Device> { device in
            device.deletedAt == nil && device.persistentModelID == deviceId
        })
        descriptor.fetchLimit = 1
        descriptor.sortBy = [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse)
        ]
        descriptor.propertiesToFetch = [
            \Device.udn, \Device.location, \Device.lastOnlineAt, \Device.lastSelectedAt,
             \Device.name, \Device.deletedAt, \.hiddenAt, \Device.lastSentToWatch, \Device.lastScannedAt,
             \Device.ethernetMAC, \Device.rtcpPort, \Device.supportsDatagram, \Device.wifiMAC,
             \Device.networkType, \Device.powerMode
        ]

        _selectedDevices = Query(
            descriptor
        )
    }

    var device: Device? {
        selectedDevices.first
    }

    var dismiss: () -> Void

    var nameValidation: String? {
        if deviceName == "" {
            "Please enter a name for your device"
        } else {
            nil
        }
    }
    var addressValidation: String? {
        if deviceIP == "" {
            "Please enter your device's IP. You can find this in your TV's Network settings"
        } else {
            nil
        }
    }
    
    var body: some View {
        if runningInPreview {
            bodyContent
        } else {
            bodyContent
                .onChange(of: device?.name) { _, new in
                    if let new = new {
                        deviceName = new
                    }
                }
                .onChange(of: device?.location) { _, new in
                    if let new = new {
                        let host = getHostPortDisplay(from: new)
                        Log.userInteraction.notice("Seeing host \(host, privacy: .public) in change")
                        deviceIP = host
                    }
                }
                .onChange(of: device?.hiddenAt) { _, newHiddenAt in
                    hidden = newHiddenAt != nil
                }
                .onAppear {
                    scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer(), updater: {
                        updater?.update()
                    })

                    deviceName = device?.name ?? getGlobalNewDeviceName()
                    let deviceUrl = device?.location ?? "192.168.0.1"
                    let host = getHostPortDisplay(from: deviceUrl)

                    Log.userInteraction.notice("Seeing host \(host, privacy: .public)")
                    deviceIP = host
                    hidden = device?.hiddenAt != nil
                }
                .onDisappear {
                    if addressValidation != nil || nameValidation != nil {
                        return
                    }
                }
        }
    }

    @ViewBuilder
    var bodyContent: some View {
        Form {
            Section(content: {
                EmptyView()
            }, header: {
                EmptyView()
            }, footer: {
                VStack {
                    HStack(alignment: .center) {
                        DataImage(from: device?.deviceIcon, fallback: "tv")
                            .frame(maxHeight: 45)
                            .padding(.horizontal, 12)
                            .padding(4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    
                    Text(device?.name ?? getGlobalNewDeviceName())
                        .font(.title3.bold())
                }
            })

            Section(String(localized: "Parameters", comment: "Settings section title indicating device parameters")) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(String(localized: "Name", comment: "Settings field label for the device name"), text: $deviceName)
                        .frame(maxWidth: .infinity)
                    if let nameValidation {
                        Text(nameValidation)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField(String(localized: "IP Address", comment: "Settings field label for the device's IP address"), text: $deviceIP)
                            .frame(maxWidth: .infinity)
                        #if !os(watchOS)
                        Spacer()
                            .frame(maxWidth: 10)

                        Link(destination: URL(string: String(localized: "https://roam.msd3.io/manually-add-tv"))!) {
                            Label("Info", systemImage: "info.circle")
                                .labelStyle(.iconOnly)
                        }
                        .foregroundStyle(Color.secondary)
                        #endif
                    }

                    if let addressValidation {
                        Text(addressValidation)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

#if !os(watchOS)
            Section(String(localized: "Capabilities", comment: "Settings section label for device ")) {
                Button(action: {
                    withAnimation {
                        showHeadphonesModeDescription = !showHeadphonesModeDescription
                    }
                }, label: {
                    LabeledContent(String(localized: "Headphones mode", comment: "Settings label for headphones mode support")) {
                        HStack(spacing: 8) {
                            if device?.supportsDatagram == true {
                                Label(String(localized: "Supported", comment: "Label indicating headphones mode is supported"), systemImage: "headphones").labelStyle(.badge(.green))
                            } else if device?.supportsDatagram == false {
                                Label(String(localized: "Not Supported", comment: "Label indicating headphones mode is not supported"), systemImage: "headphones").labelStyle(.badge(.red))
                            } else {
                                // swiftlint:disable:next line_length
                                Label(String(localized: "Support Unknown", comment: "Label indicating headphones mode support is possible but not indicated"), systemImage: "headphones").labelStyle(.badge(.yellow))
                            }

                            Image(systemName: "info.circle")
                        }
                    }
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)

                if showHeadphonesModeDescription {
                    if device?.supportsDatagram == true {
                        Text(
                            "Your Roku device supports streaming audio directly to Roam. Click the headphones button in the main view to see it in action!",
                            comment: "Descriptive caption in a device settings page"
                        )
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    } else if device?.supportsDatagram == false {
                        Text(
                            // swiftlint:disable:next line_length
                            "Some Roku devices support streaming audio directly to Roam. Unfortunately yours does not support this. To see which devices support this check out https://www.roku.com/products/compare",
                            comment: "Descriptive caption in a device settings page"
                        )
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    } else {
                        Text(
                            // swiftlint:disable:next line_length
                            "Some Roku devices support streaming audio directly to Roam. Roam hasn't been able to check for support on this device. Click the headphones button in the main view to see if it works for you or visit https://www.roku.com/products/compare to see which devices do support this feature.",
                            comment: "Descriptive caption in a device settings page"
                        )
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                }
            }
#endif
            Toggle(
                "Hide Device",
                systemImage: "eye.slash",
                isOn: $hidden
            )

            Button(role: .destructive, action: {
                // Don't block the dismiss waiting for save
                Log.userInteraction.notice("Deleting \("device", privacy: .public)")
                let deviceId = deviceId
                Task.detached {
                    DispatchQueue.main.async {
                        dismiss()
                    }
                    do {
                        try await DataHandler(modelContainer: getSharedModelContainer()).delete(deviceId)

                        Log.userInteraction.notice("Deleted device with id \(String(describing: deviceId), privacy: .public)")
                    } catch {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                    }
                    DispatchQueue.main.async {
                        updater?.update()
                    }
                }
            }, label: {
              Text("Delete Device", comment: "Text on a button to delete the device")
            })
            #if !os(macOS)
            .frame(maxWidth: .infinity)
            #endif
            .foregroundStyle(Color.red)
        }
        .onSubmit {
            if nameValidation != nil || addressValidation != nil {
                return
            }

            save()
            #if !os(watchOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                dismiss()
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationBarBackButtonHidden(true)
        .toolbar(id: "settings-detail") {
            ToolbarItem(id: "save-device", placement: .primaryAction) {
                Button(String(localized: "Back", comment: "Text on a button to save the device settings"), systemImage: "chevron.left", action: {
                    save()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismiss()
                    }
                })
            }
        }
    }
    
    func save() {
        if let device = device {
            // Try to get device id
            // Watchos can't check tcp connection, so just do the request
            let cleanedString = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            let deviceUrl = addSchemeAndPort(to: cleanedString)
            Log.data.notice("Getting device url \(deviceUrl, privacy: .public)")

            let dh = DataHandler(modelContainer: getSharedModelContainer())
            Task {
                await dh.updateDevice(device.persistentModelID, name: deviceName, location: deviceUrl, hidden: hidden)

                DispatchQueue.main.async {
                    updater?.update()
                }
            }
        }
    }
}

#if DEBUG
#Preview(
    "Device Detail View",
    traits: .fixedLayout(width: 400, height: 300)
) {
    DeviceDetailView(deviceId: getTestingDevices()[0].id, dismiss: {})
        .modelContainer(previewContainer)
}
#endif
