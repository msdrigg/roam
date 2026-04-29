import os
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(visionOS)
let deviceIconSize: CGFloat = 42.0
let circleSize: CGFloat = 14
#elseif os(macOS)
let deviceIconSize: CGFloat = 32.0
let circleSize: CGFloat = 10
#else
let deviceIconSize: CGFloat = 24.0
let circleSize: CGFloat = 10
#endif

struct SettingsView: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var deviceListLoader = DeviceListLoader(dataHandler: .shared)
    @State private var hiddenDeviceListLoader = HiddenDeviceListLoader(dataHandler: .shared)
    @State private var messageLoader = MessageListLoader(dataHandler: .shared)
    @State private var allDevices: [Device]?
    @Binding var path: [NavigationDestination]
    let destination: SettingsDestination

    @State private var scanningActor: DeviceDiscoveryActor!
    @State private var ssdpActor: DeviceDiscoveryActor!
    @State private var isScanning: Bool = false

    #if os(watchOS)
    @State private var showingAddDeviceSheet: Bool = false
    #endif

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State private var showWatchOSNote = false

#if os(watchOS)
    @EnvironmentObject private var appDelegate: RoamWatchAppDelegate
#else
    @EnvironmentObject private var appDelegate: RoamAppDelegate
#endif
    @Environment(\.layoutDirection) var layoutDirection

    @Environment(\.self) var env

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true
    @AppStorage(UserDefaultKeys.showMenuBar) private var showMenuBar: Bool = false
    @AppStorage(UserDefaultKeys.userMajorActionCount) private var majorActionsCount: Int = 0

    @State private var customAccentColor: Color = .accentColor

    @State private var variableColor: CGFloat = 0.0
    @State private var deviceError: Error?

    #if !os(watchOS)
    func initiateScan() {
        Log.scanning.notice(
            "Manual settings scan requested scanningActorReady=\(scanningActor != nil, privacy: .public) ssdpActorReady=\(ssdpActor != nil, privacy: .public) scanIpAutomatically=\(scanIpAutomatically, privacy: .public) visibleDeviceCount=\(devices.count, privacy: .public)"
        )
        Task {
            guard let scanningActor, let ssdpActor else {
                Log.scanning.warning("Manual settings scan skipped because discovery actors are not ready")
                return
            }

            self.isScanning = true
            defer {
                 self.isScanning = false
            }

            Log.scanning.notice("Manual settings scan starting IPV4 and one-shot SSDP")
            await withDiscardingTaskGroup { taskGroup in
                taskGroup.addTask {
                    await scanningActor.scanIPV4Once()
                }
                taskGroup.addTask {
                    await ssdpActor.scanSSDPOnce()
                }
            }
            Log.scanning.notice("Manual settings scan completed IPV4 and one-shot SSDP")
        }
    }
    #endif

    func saveCustomAccentColor(_ color: Color?) {
        if let color {
            let resolved = color.resolve(in: env)
            Log.data.notice("Setting color to \(resolved)")
            UserDefaults.standard.setColor(resolved, forKey: UserDefaultKeys.customAccentColor)
        } else {
            Log.data.notice("Resetting color")
            UserDefaults.standard.removeObject(forKey: UserDefaultKeys.customAccentColor)
        }
    }

    func loadCustomAccentColor() {
        customAccentColor = UserDefaults.standard.color(forKey: UserDefaultKeys.customAccentColor) ?? .accentColor
    }

    private var allDevicesById: [String: Device] {
        Dictionary((allDevices ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var devices: [Device] {
        (deviceListLoader.devices ?? []).compactMap { allDevicesById[$0] }.filter { $0.visible }
    }

    var hiddenDevices: [Device] {
        (hiddenDeviceListLoader.devices ?? []).compactMap { allDevicesById[$0] }.filter { $0.hiddenAt != nil }
    }

    private var allDeviceIds: [String] {
        (deviceListLoader.devices ?? []) + (hiddenDeviceListLoader.devices ?? [])
    }

    private var allDeviceRefreshKey: String {
        "\(allDeviceIds.joined(separator: "|"))-\(deviceListLoader.revision)-\(hiddenDeviceListLoader.revision)"
    }

    private var unreadMessages: Int {
        messageLoader.unreadCount
    }

    var body: some View {
        if runningInPreview {
            bodyContent
        } else {
            bodyContent
                .onAppear {
                    Log.lifecycle.notice("Showing \(#fileID, privacy: .public) view")
                    loadCustomAccentColor()
                }
                .onDisappear {
                    Log.lifecycle.notice("Closing \(#fileID, privacy: .public) view")
                }
                .onAppear {
                    Log.scanning.notice(
                        "SettingsView creating discovery actors scanIpAutomatically=\(scanIpAutomatically, privacy: .public)"
                    )
                    scanningActor = DeviceDiscoveryActor()
                    ssdpActor = DeviceDiscoveryActor()

                }
                .task(id: allDeviceRefreshKey) {
                    allDevices = await RoamDataHandler.shared.requestAllDevices(allDeviceIds)
                }
#if !os(watchOS)
                .task(id: "\(scanIpAutomatically)", priority: .background) {
                    Log.scanning.notice(
                        "SettingsView automatic SSDP task fired actorReady=\(ssdpActor != nil, privacy: .public) scanIpAutomatically=\(scanIpAutomatically, privacy: .public)"
                    )
                    guard scanIpAutomatically else {
                        Log.scanning.notice("SettingsView automatic SSDP task skipping because scanIpAutomatically is false")
                        return
                    }
                    guard let ssdpActor else {
                        Log.scanning.warning("SettingsView automatic SSDP task skipping because ssdpActor is nil")
                        return
                    }

                    await ssdpActor.scanSSDPContinually()
                    Log.scanning.notice("SettingsView automatic continual SSDP scan returned")
                }
#endif
#if !os(watchOS) && !os(macOS)
                .onAppear {
                    appDelegate.navigationPath.focusedWindow = .settings
                }
#endif
#if os(macOS)
                .onWindowFocused {
                    Log.lifecycle.notice("\(#fileID, privacy: .public) becoming key window")
                    appDelegate.navigationPath.focusedWindow = .settings
                }
#endif
        }
    }

    var bodyContent: some View {
        Form {
            Section {
                if devices.isEmpty {
                    Text("No devices", comment: "Placeholder for a device selector when there aren't any devices")
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(Array(devices.enumerated()), id: \.element.displayHash) { idx, device in
                        DeviceListItem(device: device, idx: idx)
                    }
                    .onDelete { indexSet in
                        let devicesToDelete = indexSet.compactMap { devices[safe: $0] }
                        Task {
                            for model in devicesToDelete {
                                do {
                                    try await RoamDataHandler.shared.deleteDevice(id: model.id)
                                } catch let error as DataHandlerError {
                                    Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                                    deviceError = error
                                    return
                                } catch {
                                    Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                                    deviceError = error
                                    return
                                }
                            }
                        }
                    }
                }
#if os(watchOS)
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
                        initiateScan()
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
                    .offset(x: layoutDirection == .rightToLeft ? -6 : 6)
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
                        initiateScan()
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
                    NavigationStack {
                        WatchOSNote()
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

                HStack {
                    Text("Accent Color", comment: "Label for accent color picker")
                    Spacer()
                    ColorPicker("", selection: Binding(get: { customAccentColor }, set: { c in
                        saveCustomAccentColor(c)
                        customAccentColor = c
                    }), supportsOpacity: false)
                        .labelsHidden()
                    Button(action: {
                        customAccentColor = .accentColor
                        saveCustomAccentColor(nil)
                    }, label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    })
                    .buttonStyle(PlainButtonStyle())
                    .help("Reset to default accent color")
                }
            }
#endif

            Section(String(localized: "Other", comment: "Settings section label")) {
#if !os(watchOS)
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

                Button(action: {
#if os(macOS)
                    openWindow(id: "messages")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApp.forceFront("messages")
                    }
#else
                    path.append(NavigationDestination.messageDestination)
#endif
                }, label: {
                    HStack {
                        if unreadMessages > 0 {
                            Label(String(localized: "Chat with the Developer", comment: "Label on a button to open the chat window"), systemImage: "message")
#if !os(watchOS)
                                .badge(unreadMessages)
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

#if !os(watchOS)
                if !hiddenDevices.isEmpty {
                    DisclosureGroup {
                        List {
                            ForEach(hiddenDevices, id: \.displayHash) { device in
                                HiddenDeviceListItem(device: device)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    if let model = hiddenDevices[safe: index] {
                                        let pid = model.id
                                        Task {
                                            do {
                                                try await RoamDataHandler.shared.deleteDevice(id: pid)
                                            } catch let error as DataHandlerError {
                                                Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
                                                deviceError = error
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Hidden Devices", systemImage: "eye.slash")
                    }
                    .disclosureGroupStyle(StandardDisclosureGroupStyle())
                }
#endif
            }

            Section {
                NavigationLink(String(localized: "About", comment: "Text on a navigation link to the about page"), value: NavigationDestination.aboutDestination)
            }
        }
#if os(watchOS)
        .sheet(isPresented: $showingAddDeviceSheet) {
            NavigationStack {
                AddDeviceFlow()
            }
        }
#else
        .sheet(isPresented: appDelegate.navigationPath.showingAddDevice(for: .settings)) {
            AddDeviceFlow()
        }
#endif
#if !os(watchOS) && !os(macOS)
        .refreshable {
            initiateScan()
        }
        .toolbar(id: "settings-global") {
            ToolbarItem(id: "add-device", placement: .primaryAction) {
                addDeviceButton
            }
        }
#endif
#if !os(watchOS)
        .navigationTitle(String(localized: "Settings", comment: "Navigation title on the settings page"))
#endif
        .formStyle(.grouped)
        .alertingError(message: "Failed to Delete Device", error: $deviceError)
        .customAccentColorTint()
    }

    @ViewBuilder
    var addDeviceButton: some View {
        Button(String(localized: "Add a device manually", comment: "Label on a button to add a device"), systemImage: "plus") {
            #if os(watchOS)
            showingAddDeviceSheet = true
            #else
            appDelegate.navigationPath.showAddDevice = true
            #endif
        }
        #if !os(watchOS) && !WIDGET
        .customKeyboardShortcut(.addDevice)
        #endif
    }
}

struct MacSettings: View {
    @State var navPath: [NavigationDestination] = []
    var body: some View {
        SettingsNavigationWrapper(path: $navPath, showsMacSettingsControls: true) {
            SettingsView(path: $navPath, destination: .global)
        }
        .frame(minWidth: 300)
    }
}

#if DEBUG
#Preview(
    "Device List",
     traits: .fixedLayout(width: 400, height: 300)
) {
    @Previewable @State var path: [NavigationDestination] = []
    return SettingsView(path: $path, destination: .global)
}
#endif
