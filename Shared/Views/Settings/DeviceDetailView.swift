struct DeviceDetailView: View {
    @State private var scanningActor: DeviceDiscoveryActor!

    var deviceId: PersistentIdentifier
    @State var deviceName: String = getGlobalNewDeviceName()
    @State var deviceIP: String = "192.168.0.1"

    @State var showHeadphonesModeDescription: Bool = false

    @Query private var selectedDevices: [Device]
    @Environment(\.uuidUpdater) private var updater

    @MainActor
    init(deviceId: PersistentIdentifier, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        self.deviceId = deviceId
        var descriptor = FetchDescriptor<Device>(predicate: #Predicate<Device> { device in
            device.deletedAt == nil && device.persistentModelID == deviceId
        })
        descriptor.fetchLimit = 1
        descriptor.sortBy = [
            SortDescriptor(\.lastSelectedAt, order: .reverse)
        ]
        descriptor.propertiesToFetch = [
            \.udn, \.location, \.lastOnlineAt, \.lastSelectedAt,
             \.name, \.deletedAt, \.lastSentToWatch, \.lastScannedAt,
             \.ethernetMAC, \.rtcpPort, \.supportsDatagram, \.wifiMAC,
             \.networkType, \.powerMode
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
        Form {
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
            Section(String(localized: "Headphones Mode", comment: "Settings section label for headphones mode")) {
                Button(action: {
                    withAnimation {
                        showHeadphonesModeDescription = !showHeadphonesModeDescription
                    }
                }, label: {
                    LabeledContent(String(localized: "Supports headphones mode", comment: "Settings label for headphones mode support")) {
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

            Section(String(localized: "Info", comment: "Settings section title for the Info section")) {
                LabeledContent(String(localized: "Id", comment: "Settings label for the device's id")) {
                    Text(device?.udn ?? "--")
                }

                LabeledContent(String(localized: "RTCP Port", comment: "Settings label for the device's RTCP port")) {
                    if let rtcpPort = device?.rtcpPort {
                        Text(rtcpPort, format: .number
                            .grouping(.never))
                    } else {
                        Text("Unknown", comment: "Placeholder for unknown information")
                    }
                }
            }
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
        .onAppear {
            deviceName = device?.name ?? getGlobalNewDeviceName()
            let deviceUrl = device?.location ?? "192.168.0.1"
            let host = getHostPortDisplay(from: deviceUrl)

            Log.userInteraction.notice("Seeing host \(host, privacy: .public)")
            deviceIP = host
        }
        .onDisappear {
            if addressValidation != nil || nameValidation != nil {
                return
            }
        }
        .toolbar(id: "settings-detail") {
            ToolbarItem(id: "save-device", placement: .primaryAction) {
                Button(String(localized: "Save", comment: "Text on a button to save the device settings"), systemImage: "checkmark", action: {
                    save()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismiss()
                    }
                })
            }

            ToolbarItem(id: "delete-device", placement: .destructiveAction) {
                Button(String(localized: "Delete", comment: "Text on a button to delete the device"), systemImage: "trash", role: .destructive, action: {
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
                })
                .foregroundStyle(Color.red)
            }
        }
        .onAppear {
            scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer(), updater: {
                updater?.update()
            })
        }

#if os(macOS)
        .padding()
#endif
    }

    func save() {
        if let device = device {
            let pid = device.persistentModelID
            let udn = device.udn
            Task.detached {
                await saveDevice(
                    existingDeviceId: pid,
                    existingUDN: udn,
                    newIP: deviceIP,
                    newDeviceName: deviceName,
                    dataHandler: DataHandler(
                        modelContainer: getSharedModelContainer()
                    )
                )

                DispatchQueue.main.async {
                    updater?.update()
                }
            }
        }
    }
}
