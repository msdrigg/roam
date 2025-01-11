import os
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(tvOS)
let deviceIconSize: CGFloat = 64.0
let circleSize: CGFloat = 18
#elseif os(visionOS)
let deviceIconSize: CGFloat = 42.0
let circleSize: CGFloat = 14
#elseif os(macOS)
let deviceIconSize: CGFloat = 32.0
let circleSize: CGFloat = 10
#else
let deviceIconSize: CGFloat = 24.0
let circleSize: CGFloat = 10
#endif

private let messageFetchDescriptor: FetchDescriptor<Message> = {
    var fd = FetchDescriptor(
        predicate: #Predicate<Message> {
            !$0.viewed
        }
    )
    return fd
}()

private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name)]
    )
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt, \.deviceIcon]
    return fd
}()

struct SettingsView: View {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @Query(deviceFetchDescriptor) private var devices: [Device]
    @Query(messageFetchDescriptor) private var unreadMessages: [Message]
    @Binding var path: [NavigationDestination]
    let destination: SettingsDestination

    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var isScanning: Bool = false

    @State private var showWatchOSNote = false
    @Environment(\.uuidUpdater) private var updater

#if !os(watchOS)
    @EnvironmentObject private var appDelegate: RoamAppDelegate
#endif

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldDisableAllAutoScanning) private var disableAllScanning: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true
    @AppStorage(UserDefaultKeys.showMenuBar) private var showMenuBar: Bool = false
    @AppStorage(UserDefaultKeys.userMajorActionCount) private var majorActionsCount = 0

    @State private var reportingDebugLogs: Bool = false
    @State private var debugLogReportID: String?

    @State private var variableColor: CGFloat = 0.0

    func reportDebugLogs() {
        Task {
            reportingDebugLogs = true
            defer { reportingDebugLogs = false }
            Self.logger.info("Starting to send logs")
            let logs = await getDebugInfo(container: getSharedModelContainer())
            Self.logger.info("Sending logs \(logs.installationInfo.userId)")

            do {
                try await uploadDebugLogs(logs: logs)
                try await sendMessage(message: "Diagnostics Shared at \(Date.now.formatted())", apnsToken: nil)

                Self.logger.info("Upload successful")
                DispatchQueue.main.async {
#if os(watchOS)
                    debugLogReportID = logs.installationInfo.userId
#elseif os(macOS)
                    openWindow(id: "messages")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
#else
                    path.append(NavigationDestination.messageDestination)
#endif
                }
            } catch {
                Self.logger.error("Failed to upload logs: \(error)")
            }
        }
    }

    nonisolated func triggerUpdate() {
        DispatchQueue.main.async {
            self._devices.update()
            Self.logger.info("Getting new update for value \(String(describing: self.updater?.uuid))")
            self.updater?.update()
            Self.logger.info("Getting new update 2 for value \(String(describing: self.updater?.uuid))")
        }
    }

    var body: some View {
        Form {
            Section {
                if devices.isEmpty {
                    Text("No devices", comment: "Placeholder for a device selector when there aren't any devices")
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(Array(devices.enumerated()), id: \.element.displayHash) { idx, device in
                        DeviceListItem(device: device)
                            .accessibilityIdentifier("DeviceItem_\(idx)")
#if !os(watchOS)
                            .contextMenu {
                                Button(role: .destructive) {
                                    let pid = device.persistentModelID
                                    Task.detached {
                                        do {
                                            Self.logger.error("HI")
                                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                                            Self.logger
                                                .info(
                                                    "Deleted device with id \(String(describing: pid))"
                                                )
                                            self.triggerUpdate()
                                        } catch {
                                            Self.logger.error("Error deleting device \(error)")
                                        }
                                    }
                                } label: {
                                    Label(String(localized: "Delete", comment: "Label on a button to delete a device"), systemImage: "trash")
                                }
                                NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.persistentModelID)) {
                                    Label(String(localized: "Edit", comment: "Label on a button to edit a device"), systemImage: "pencil")
                                }
                            }
#endif
#if !os(tvOS)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    let pid = device.persistentModelID
                                    Task.detached {
                                        do {
                                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                                            self.triggerUpdate()
                                        } catch {
                                            Self.logger.error("Error deleting device \(error)")
                                        }
                                    }

                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
#endif
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            if let model = devices[safe: index] {
                                let pid = model.persistentModelID
                                Task.detached {
                                    do {
                                        try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                                        self.triggerUpdate()
                                    } catch {
                                        Self.logger.error("Error deleting device \(error)")
                                    }
                                }
                            }
                        }
                    }
                }
#if os(watchOS) || os(tvOS)
                addDeviceButton
#endif

#if os(macOS)
                HStack {
                    Spacer()

                    addDeviceButton
                }
#endif
            } header: {
#if os(macOS) || os(visionOS)
                HStack {
                    Text("Devices")
                    Spacer()
                    Button(isScanning ? "Scanning for devices..." : "Scan for devices", systemImage: isScanning ? "rays" : "arrow.clockwise") {
                        Task {
                            isScanning = true
                            defer {
                                isScanning = false
                            }

                            await scanningActor.scanIPV4Once()
                        }
                    }
                    .symbolEffect(.variableColor, isActive: isScanning)
                    .disabled(isScanning)
                    #if os(macOS)
                    .buttonStyle(PaddedHoverButtonStyle(padding: .init(
                        top: 3,
                        leading: 8,
                        bottom: 3,
                        trailing: 8
                    )))
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .help("Scan for devices")
                    .labelStyle(.iconOnly)
                    .offset(x: 6)
                }
#else
                Text("Devices", comment: "Header in device selection menu")
#endif
            } footer: {
#if !os(watchOS) && !os(macOS) && !os(visionOS)
                if isScanning {
                    Label("Scanning for devices...", systemImage: "rays")
                        .symbolEffect(.variableColor, isActive: isScanning)
                        .font(.caption)
                } else {
                    Button(String(localized: "Refresh devices", comment: "Button text to refresh the device list"), systemImage: "arrow.clockwise") {
                        Task {
                            isScanning = true
                            defer {
                                isScanning = false
                            }

                            await scanningActor.scanIPV4Once()
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
#else
                EmptyView()
#endif
            }

#if os(watchOS)
            Button(String(localized: "WatchOS Note", comment: "Description on a button to see info about watchOS limitations"), systemImage: "info.circle.fill", action: { showWatchOSNote = true })
                .sheet(isPresented: $showWatchOSNote) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                // swiftlint:disable:next line_length
                                "Due to WatchOS limitations, you may need to enable \"Permissive\" Network Access on your Roku TV. You can do this by going to Settings -> System -> Advanced System Settings -> Control by mobile apps",
                                comment: "WatchOS indicator showing that watchOS can't auto-discover TV's due to network restrictions"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            Text(
                                "Additinoally, WatchOS prevents us from discovering TV's on the local network.",
                                comment: "WatchOS indicator showing that watchOS can't auto-discover TV's due to network restrictions"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            Text(
                                // swiftlint:disable:next line_length
                                "To work around this limitation, first discover devices on the iPhone app and then the devices will be transferred in the background from the iPhone to the watch (or you can manually add the TV if you can get it's IP address).",
                                comment: "Description of watchOS discovery alternatives"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            Text(
                                // swiftlint:disable:next line_length
                                "Please be patient, because I don't have an apple watch so I can't test how effective this is. Please reach out if you aren't able to get this to work :). You can email me at roam-support@msd3.io",
                                comment: "Description of watchOS discovery alternatives"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
#endif

#if !os(watchOS)
            Section(String(localized: "Behavior", comment: "Settings section label")) {
#if os(iOS)
                Toggle(String(localized: "Use volume buttons to control TV volume", comment: "Label on a settings toggle"), isOn: $controlVolumeWithHWButtons)
#endif

                #if os(macOS)
                Toggle(String(localized: "Show menu bar icon", comment: "Label on a settings toggle"), isOn: $showMenuBar)
                #endif

                Toggle(
                    String(localized: "Scan for devices automatically", comment: "Label on a settings toggle"),
                    isOn: Binding<Bool>(get: {
                        return scanIpAutomatically
                    }, set: { newValue in
                        withAnimation {
                            scanIpAutomatically = newValue
                        }
                    })
                )
            }
#endif

            Section(String(localized: "Other", comment: "Settings section label")) {
#if !os(tvOS) && !os(watchOS)
                NavigationLink(value: NavigationDestination.keyboardShortcutDestinaion, label: {
                    HStack {
                        Label(String(localized: "Keyboard shortcuts", comment: "Label on a link to open the keyboard shortcuts window"), systemImage: "keyboard")
                        Spacer()
                    }
                })
                .customKeyboardShortcut(.keyboardShortcuts)
                .buttonStyle(.borderless)
#if os(macOS)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
#endif
#endif
#if !os(tvOS)
                if majorActionsCount > 5 {
                    ShareLink(
                        item: URL(string: "https://apps.apple.com/us/app/roam-a-better-remote-for-roku/id6469834197")!
                    ) {
                        HStack {
                            Label(String(localized: "Gift Roam to a friend", comment: "Description on a button to share the link to this application"), systemImage: "app.gift")
                            Spacer()
                        }
                    }
#if os(macOS)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
#endif
                }
#endif

#if !os(watchOS)
                Button(action: {
#if os(macOS)
                    openWindow(id: "messages")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
#else
                    path.append(NavigationDestination.messageDestination)
#endif
                }, label: {
                    HStack {
                        if unreadMessages.count > 0 {
                            Label(String(localized: "Chat with the Developer", comment: "Label on a button to open the chat window"), systemImage: "message")
#if !os(tvOS)
                                .badge(unreadMessages.count)
#endif
                        } else {
                            Label(String(localized: "Chat with the Developer", comment: "Label on a button to open the chat window"), systemImage: "message")
                        }
                        Spacer()
                    }
#if os(macOS)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
#endif
                })
#if os(macOS)
                .buttonStyle(.plain)
#endif

#endif

#if os(watchOS) || os(tvOS)
                Button(action: { reportDebugLogs() }, label: {
                    HStack {
                        Label(
                            // swiftlint:disable:next line_length
                            reportingDebugLogs ? String(localized: "Collecting Diagnostics...", comment: "Description on a button that is collecting app diagnostics") : String(localized: "Share diagnostics", comment: "Label on a button to share app diagnostics"),
                            systemImage: "square.and.arrow.up"
                        )
                        Spacer()
                        if reportingDebugLogs {
                            Image(systemName: "rays")
                                .symbolEffect(.variableColor, isActive: true)
                        }
                    }
                })
                .sheet(isPresented: Binding<Bool>(
                    get: { debugLogReportID != nil && !reportingDebugLogs },
                    set: { if !$0 { debugLogReportID = nil } }
                )) {
                    VStack {
                        Text("Your diagnostic report has been created with ID \"\(debugLogReportID ?? "unknown")\"", comment: "Success indicator on a diagnostic report flow")
                            .font(.headline)
                            .padding(.bottom, 2)
                        Text("Please send an email to roam-support@msd3.io including the report ID any other feedback", comment: "Caption on a diagnostic report flow")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 2)
                        HStack {
#if !os(tvOS)
                            ShareLink(item: String(localized: """
                                Hi Roam Support (roam-support@msd3.io),

                                <Add Feedback Here>

                                ---
                                Debug ID \(debugLogReportID ??
                                                    "unknown")
                                """, comment: "Email body template for a support email"), subject: Text("Roam Feedback", comment: "Subject line in email requesting help")) {
                                Label(String(localized: "Open Email Template", comment: "Label on a button to open an email"), systemImage: "square.and.arrow.up")
                            }
#endif
                            Button(String(localized: "Close", comment: "Label on a button to close a menu"), systemImage: "xmark", role: .destructive) { debugLogReportID = nil }
                        }
                    }
                    .padding()
                }
#endif
            }

            Section {
                NavigationLink(String(localized: "About", comment: "Text on a navigation link to the about page"), value: NavigationDestination.aboutDestination)
            }
        }
        .id(updater?.uuid.uuidString ?? "--")
        .onAppear {
            if destination == .debugging {
                reportDebugLogs()
            }
        }
        .onAppear {
            Self.logger.info("Showing view")
        }
        .onDisappear {
            Self.logger.info("Closing view")
        }
#if !os(watchOS)
        .onAppear {
            Self.logger.info("")
            appDelegate.navigationPath.showingSettingsView = true
        }
        .onDisappear {
            appDelegate.navigationPath.showingSettingsView = false
        }
#endif

#if !os(macOS) && !os(watchOS) && !os(tvOS)
        .refreshable {
            isScanning = true
            defer {
                isScanning = false
            }

            await scanningActor.scanIPV4Once()
        }
        .toolbar(id: "settings-global") {
            ToolbarItem(id: "add-device", placement: .primaryAction) {
                addDeviceButton
            }
        }
#endif
#if !os(watchOS) && !os(tvOS)
        .navigationTitle(String(localized: "Settings", comment: "Navigation title on the settings page"))
#endif
        .formStyle(.grouped)
        .onAppear {
            scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer(), updater: {
                updater?.update()
            })
        }
#if !os(watchOS)
        .task(priority: .background) {
            if !scanIpAutomatically {
                return
            }

            defer {
                isScanning = false
            }

            isScanning = true
            await scanningActor.scanIPV4Once()
        }
#endif
    }

    @ViewBuilder
    var addDeviceButton: some View {
        Button(String(localized: "Add a device manually", comment: "Label on a button to add a device"), systemImage: "plus") {
            Task.detached {
                let persistentId = await DataHandler(modelContainer: getSharedModelContainer()).addOrReplaceDevice(location: "http://192.168.0.1:8060/", friendlyDeviceName: String(localized: "New device"), udn: "roam:newdevice-\(UUID().uuidString)"
                )
                Self.logger.info("Added empty device with persistent ID \(String(describing: persistentId), privacy: .public)")
            }
        }
    }
}

struct DeviceListItem: View {
    @Bindable var device: Device

    var body: some View {
        NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.persistentModelID)) {
            HStack(alignment: .center) {
                VStack(alignment: .center) {
                    DataImage(from: device.deviceIcon, fallback: "tv")
                        .resizable()
#if !os(tvOS)
                        .controlSize(.extraLarge)
#endif
                        .aspectRatio(contentMode: .fit)
                        .frame(width: deviceIconSize, height: deviceIconSize)
                        .padding(4)
                }

                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .foregroundColor(device.isOnline() || inScreenshotTestingContext() ? Color.green : Color.gray)
                            .frame(width: circleSize, height: circleSize)
                        Text(device.name).lineLimit(1)
                    }
                    WrappingHStack(
                        alignment: .bottomLeading,
                        horizontalSpacing: 12,
                        verticalSpacing: 12,
                        fitContentWidth: true
                    ) {
                        Text(getHostPortDisplay(from: device.location)).foregroundStyle(Color.secondary).lineLimit(1)
#if !os(watchOS)
                        if device.supportsDatagram == true {
                            Label(String(localized: "Supported", comment: "Label indicating headphones mode is supported"), systemImage: "headphones").labelStyle(.badge(.green))
                        } else if device.supportsDatagram == false {
                            Label(String(localized: "Not Supported", comment: "Label indicating headphones mode is not supported"), systemImage: "headphones").labelStyle(.badge(.red))
                        } else {
                            // swiftlint:disable:next line_length
                            Label(String(localized: "Support Unknown", comment: "Label indicating headphones mode support is possible but not indicated"), systemImage: "headphones").labelStyle(.badge(.yellow))
                        }
#endif
                    }
                }
            }
        }
    }
}

struct MacSettings: View {
    @State var navPath: [NavigationDestination] = []
    var body: some View {
        SettingsNavigationWrapper(path: $navPath) {
            SettingsView(path: $navPath, destination: .global)
        }
    }
}

struct DeviceDetailView: View {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DeviceDetailView.self)
    )

    @State private var scanningActor: DeviceDiscoveryActor!

    var deviceId: PersistentIdentifier
    @State var deviceName: String = String(localized: "New device")
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
#if os(tvOS)
                Button(String(localized: "Save", comment: "Text on a button to save the device settings"), systemImage: "checkmark", action: {
                    save()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismiss()
                    }
                })
                    .disabled(nameValidation != nil || addressValidation != nil)

                Button(String(localized: "Delete", comment: "Text on a button to delete the device"), systemImage: "trash", role: .destructive, action: {
                    // Don't block the dismiss waiting for save
                    Self.logger.info("Deleting device")
                    Task.detached {
                        do {
                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(deviceId)
                            self.triggerUpdate()

                            Self.logger
                                .info("Deleted device with id \(String(describing: deviceId))")
                        } catch {
                            Self.logger.error("Error deleting device \(error)")
                        }
                        DispatchQueue.main.async {
                            dismiss()
                        }
                    }
                })
                .foregroundStyle(Color.red)
#endif
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
                LabeledContent(String(localized: "Last Selected", comment: "Settings label for the device's last selection time")) {
                    Text(device?.lastSelectedAt?.formatted() ?? String(localized: "Never", comment: "Label indicating a device was never connected"))
                }
                LabeledContent(String(localized: "Last Online", comment: "Settings label for the device's last online time")) {
                    Text(device?.lastOnlineAt?.formatted() ?? String(localized: "Never", comment: "Label indicating a device was never connected"))
                }

                LabeledContent(String(localized: "Power State", comment: "Settings label for the device's current power state")) {
                    Text(device?.powerMode ?? "--")
                }

                LabeledContent(String(localized: "Network State", comment: "Settings label for the device's current network state")) {
                    Text(device?.networkType ?? "--")
                }

                LabeledContent(String(localized: "WiFi MAC", comment: "Settings label for the device's WiFi MAC address")) {
                    Text(device?.wifiMAC ?? "--")
                }

                LabeledContent(String(localized: "Ethernet MAC", comment: "Settings label for the device's Ethernet MAC address")) {
                    Text(device?.ethernetMAC ?? "--")
                }

                LabeledContent(String(localized: "RTCP Port", comment: "Settings label for the device's RTCP port")) {
                    if let rtcpPort = device?.rtcpPort {
                        Text(rtcpPort, format: .number
                            .grouping(.never))
                    } else {
                        Text("Unknown", comment: "Placeholder for unknown information")
                    }
                }
#if os(tvOS)
                .focusable()
#endif
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
                Self.logger.info("Seeing host \(host) in change")
                deviceIP = host
            }
        }
        .onAppear {
            deviceName = device?.name ?? String(localized: "New device")
            let deviceUrl = device?.location ?? "192.168.0.1"
            let host = getHostPortDisplay(from: deviceUrl)

            Self.logger.info("Seeing host \(host)")
            deviceIP = host
        }
        .onDisappear {
            if addressValidation != nil || nameValidation != nil {
                return
            }
        }
#if !os(tvOS)
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
                    Self.logger.info("Deleting device")
                    let deviceId = deviceId
                    Task.detached {
                        DispatchQueue.main.async {
                            dismiss()
                        }
                        do {
                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(deviceId)

                            Self.logger.info("Deleted device with id \(String(describing: deviceId))")
                        } catch {
                            Self.logger.error("Error deleting device \(error)")
                        }
                        DispatchQueue.main.async {
                            updater?.update()
                        }
                    }
                })
                .foregroundStyle(Color.red)
            }
        }
#endif
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

@MainActor
public extension Binding where Value == Bool {
    /// Creates a binding by mapping an optional value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` the value
    /// of `bindingToOptional`'s `wrappedValue` is set to `nil`.
    ///
    /// Setting the value of the produce binding to `true` does nothing and
    /// will log an error.
    ///
    /// - parameter bindingToOptional: A `Binding` to an optional value, used to calculate the `wrappedValue`.
    init(mappedTo bindingToOptional: Binding<(some Any)?>) {
        self.init(
            get: { bindingToOptional.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    bindingToOptional.wrappedValue = nil
                } else {
                    os_log(
                        .error,
                        "Optional binding mapped to optional has been set to `true`, which will have no effect. Current value: %@",
                        String(describing: bindingToOptional.wrappedValue)
                    )
                }
            }
        )
    }
}

public extension Binding {
    /// Returns a binding by mapping this binding's value to a `Bool` that is
    /// `true` when the value is non-`nil` and `false` when the value is `nil`.
    ///
    /// When the value of the produced binding is set to `false` this binding's value
    /// is set to `nil`.
    @MainActor func mappedToBool<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(mappedTo: self)
    }
}

#if DEBUG
#Preview(
    "Device List",
     traits: .fixedLayout(width: 100, height: 300)
) {
    @Previewable @State var path: [NavigationDestination] = []
    return SettingsView(path: $path, destination: .global)
        .modelContainer(previewContainer)
}

#Preview(
    "Device Detail",
    traits: .fixedLayout(width: 100, height: 300)
) {
    DeviceDetailView(deviceId: getTestingDevices()[0].persistentModelID) {}
}
#endif
