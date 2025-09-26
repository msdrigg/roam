import os.log
import SwiftUI
import TipKit
import ImageIO

@main
struct RoamWatch: App {
    @WKApplicationDelegateAdaptor var appDelegate: RoamWatchAppDelegate

    init() {
        Log.lifecycle.notice("Getting WatchConnectivity \(String(describing: WatchConnectivity.shared), privacy: .public)")

        let dontKillAssertion = QActivityRunInBackgroundAssertion(name: "Tips.configure")
        if dontKillAssertion.isReleased() {
            return
        }
        defer {
            dontKillAssertion.release()
        }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: mainAppGroup))
        ])
        migrateOffSwiftData()
        Task {
            await RoamDataHandler.shared.initialize()
        }
    }

    private var navigationPath: Binding<[NavigationDestination]> {
        return Binding(
            get: { appDelegate.navigationPath.navigationPath },
            set: {
                appDelegate.navigationPath.navigationPath = $0
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            WatchAppView(navigationPath: navigationPath)
        }
    }
}

let DPAD: [[RemoteButton?]] = [
    [
        .back, .up, .power,
    ],
    [
        .left, .select, .right,
    ],
    [
        .volumeDown, .down, .volumeUp,
    ],
]

let CONTROLS: [[RemoteButton?]] = [
    [
        .instantReplay, .home, .options,
    ],
    [
        .rewind, .playPause, .fastForward,
    ],
    [
        .volumeDown, .mute, .volumeUp,
    ],
]

struct WatchAppView: View {
    @State private var scanningActor: DeviceDiscoveryActor!

    @EnvironmentObject private var appDelegate: RoamWatchAppDelegate
    @State private var primaryDeviceLoader = PrimaryDeviceLoader(dataHandler: RoamDataHandler.shared)
    @State private var showDeviceList: Bool = false
    @State private var showingAddDeviceSheet: Bool = false

    @Binding var navigationPath: [NavigationDestination]

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDevice: Device? {
        primaryDeviceLoader.device
    }

    @MainActor
    var mainBody: some View {
        SettingsNavigationWrapper(path: $navigationPath) {
            TabView {
                if selectedDevice == nil {
                    VStack {
                        Button(action: {
                            showingAddDeviceSheet = true
                        }, label: {
                            Label(String(localized: "Add a device manually", comment: "Label on a button to open the device setup page"), systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        })
                        NetworkConnectivityBanner()
                        Spacer()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .labelStyle(.titleAndIcon)
                } else {
                    NetworkConnectivityBanner()
                }

                ButtonGridView(device: selectedDevice, controls: DPAD)
                    .disabled(selectedDevice == nil)

                ButtonGridView(device: selectedDevice, controls: CONTROLS)
                    .disabled(selectedDevice == nil)

                if let device = selectedDevice {
                    AppListViewWrapper(device: device)
                }
            }
            .sheet(isPresented: $showingAddDeviceSheet) {
                NavigationStack {
                    AddDeviceFlow()
                }
            }
            .accessibilityIdentifier("MainTabView")
            .navigationTitle(selectedDevice?.name ?? String(localized: "No device"))
            .toolbar(id: "watch") {
                ToolbarItem(id: "device-picker", placement: .topBarLeading) {
                    DevicePicker(
                        device: selectedDevice,
                        showingPicker: $showDeviceList
                    )
                    .font(.body)
                }
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                scanningActor = DeviceDiscoveryActor()
            }
            .customAccentColorTint()
        }
    }

    var body: some View {
        if runningInPreview {
            mainBody
        } else {
            mainBody
                .task(id: selectedDevice?.id, priority: .medium) {
                    for await _ in exponentialBackoff(min: 30, max: 3600) {
                        if let selectedDevice {
                            Log.connection
                                .info("Refreshing device \(selectedDevice.location, privacy: .public) after backoff")
                            if Task.isCancelled {
                                return
                            }
                            let handler = try? RoamDataHandler.sharedChecked()
                            await handler?.refreshDevice(client: WatchOSRefreshClient(id: selectedDevice.id, location: selectedDevice.location))
                        } else {
                            Log.connection.info("No selected device to refresh")
                            return
                        }
                    }
                }
        }
    }
}

struct AppListViewWrapper: View {
    private let device: Device
    @State private var appLoader: DeviceAppsLoader

    init(device: Device) {
        self.device = device
        appLoader = DeviceAppsLoader(deviceId: device.id, dataHandler: RoamDataHandler.shared)
    }

    var body: some View {
        AppListView(device: device, apps: appLoader.apps ?? [], onClick: { app in
            Task {
                try? await appLoader.setSelectedApp(app.id)
            }
        })
    }
}

#if DEBUG
#Preview {
    WatchAppView(navigationPath: Binding(
        get: {[]},
        set: {_ in }
    ))
}
#endif
