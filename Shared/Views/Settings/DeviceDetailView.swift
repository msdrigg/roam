import SwiftUI
import SwiftData

struct DeviceDetailView: View {
    @State private var scanningActor: DeviceDiscoveryActor!

    var deviceId: PersistentIdentifier
    @State var deviceName: String = getGlobalNewDeviceName()
    @State var deviceIP: String = "192.168.0.1"
    @State var hidden: Bool = false

    @State var showHeadphonesModeDescription: Bool = false
    @State private var deviceError: Error?
    @State private var errorMessage: String = ""

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
        }, sortBy: [
            SortDescriptor(\Device.lastSelectedAt, order: .reverse)
        ])
        descriptor.fetchLimit = 1

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
                    scanningActor = DeviceDiscoveryActor(updater: {
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
                        FallibleImage(from: device?.iconURL, fallback: "tv", maxSize: 120)
#if os(macOS)
                            .frame(maxWidth: 120, maxHeight: 45)
#else
                            .frame(maxWidth: 120, maxHeight: 85)
#endif
                            .padding(.horizontal, 12)
                            .padding(4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Text(device?.name ?? getGlobalNewDeviceName())
                    #if os(macOS)
                        .font(.title3.bold())
                    #else
                        .font(.headline)
                    #endif
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
#if os(watchOS)
                        .textContentType(.URL)
#elseif !os(macOS)
                        .keyboardType(.numbersAndPunctuation)
#endif
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
#if !os(watchOS)
            Toggle(
                "Hide Device",
                isOn: $hidden
            )
#endif

            Button(role: .destructive, action: {
                Log.userInteraction.notice("Deleting \("device", privacy: .public)")
                let deviceId = deviceId
                Task {
                    // Don't block the dismiss waiting for save
                    DispatchQueue.main.async {
                        dismiss()
                    }
                    do {
                        try await RoamDataHandler().delete(deviceId)

                        Log.userInteraction.notice("Deleted device with id \(String(describing: deviceId), privacy: .public)")
                    } catch {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                        errorMessage = "Failed to Delete Device"
                        deviceError = error
                    }
                    DispatchQueue.main.async {
                        updater?.update()
                    }
                }
            }, label: {
              Text("Delete Device", comment: "Text on a button to delete the device")
            })
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderless)
            .foregroundStyle(Color.red)
        }
        .onSubmit {
            if nameValidation != nil || addressValidation != nil {
                return
            }

            Log.userInteraction.notice("Saving device settings due to submit--\(deviceIP)-\(hidden)-\(deviceName)")
            save()
            #if !os(watchOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                dismiss()
            }
            #endif
        }
        .onChange(of: "\(deviceIP)-\(hidden)-\(deviceName)", initial: false) {
            Log.userInteraction.notice("Autosaving device settings")
            save()
        }
        .formStyle(.grouped)
        .alertingError(message: errorMessage, error: $deviceError)
    }

    func save() {
        if let device = device {
            // Try to get device id
            // Watchos can't check tcp connection, so just do the request
            let cleanedString = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            let deviceUrl = addSchemeAndPort(to: cleanedString)
            Log.data.notice("Getting device url \(deviceUrl, privacy: .public)")

            let dh = RoamDataHandler()
            Task {
                do {
                    try await dh.updateDevice(device.persistentModelID, name: deviceName, location: deviceUrl, hidden: hidden)

                    DispatchQueue.main.async {
                        updater?.update()
                    }
                } catch {
                    Log.data.info("Error updating device \(error, privacy: .public)")
                    errorMessage = "Failed to Save Device Settings"
                    deviceError = error
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
