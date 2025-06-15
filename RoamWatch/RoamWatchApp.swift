import os.log
import SwiftData
import SwiftUI
import TipKit
import ImageIO

@main
struct RoamWatch: App {
    @WKApplicationDelegateAdaptor var appDelegate: RoamWatchAppDelegate

    init() {
        _ = getSharedModelContainer()

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: mainAppGroup))
        ])

        Log.lifecycle.notice("Getting WatchConnectivity \(String(describing: WatchConnectivity.shared), privacy: .public)")
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

    @Query(deviceFetchDescriptor()) private var devices: [Device]
    @State private var manuallySelectedDevice: Device?
    @State private var showDeviceList: Bool = false
    @State private var showingAddDeviceSheet: Bool = false

    @Binding var navigationPath: [NavigationDestination]

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDevice: Device? {
        manuallySelectedDevice ?? devices.min { d1, d2 in
            (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
        }
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

                        Spacer()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .labelStyle(.titleAndIcon)
                }

                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: DPAD)
                    .disabled(selectedDevice == nil)

                ButtonGridView(device: selectedDevice?.toAppEntity(), controls: CONTROLS)
                    .disabled(selectedDevice == nil)

                if let device = selectedDevice {
                    AppListViewWrapper(device: device.toAppEntity())
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
                        devices: devices.filter({$0.visible}),
                        device: Binding(get: {
                            manuallySelectedDevice ?? selectedDevice
                        }, set: { device in
                            manuallySelectedDevice = device
                        }),
                        showingPicker: $showDeviceList
                    )
                    .font(.body)
                }
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                scanningActor = DeviceDiscoveryActor(updater: { })
            }
        }
    }

    var body: some View {
        if runningInPreview {
            mainBody
        } else {
            mainBody
                .task {
                    if loadTestingData() {
                        // swiftlint:disable:next force_try
                        try! await RoamDataHandler.checkedCreate().loadTestData()
                    } else if usingTestingDataContainer() {
                        // swiftlint:disable:next force_try
                        try! await RoamDataHandler.checkedCreate().clearData()
                    }
                }
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    for await _ in exponentialBackoff(min: 30, max: 3600) {
                        if let selectedDevice {
                            Log.connection
                                .info("Refreshing device \(selectedDevice.location, privacy: .public) after backoff")
                            if Task.isCancelled {
                                return
                            }
                            let handler = try? RoamDataHandler.checkedCreate()
                            await handler?.refreshDevice(client: WatchOSRefreshClient(id: selectedDevice.persistentModelID, location: selectedDevice.location))
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
    private let device: DeviceAppEntity
    @Query private var apps: [AppLink]
    @State var cachedAppLinks: [AppLink]

    var appIdsIconsHashed: Int {
        var appLinkPairs: Set<String> = Set()
        for app in apps {
            appLinkPairs.insert("\(app.id);\(app.iconHash ?? "--")")
        }

        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }

    init(device: DeviceAppEntity) {
        let pid = device.udn

        _apps = Query(
            filter: #Predicate<AppLink> {
                $0.deviceUid == pid && $0.deletedAt == nil
            },
            sort: \AppLink.lastSelected,
            order: .reverse
        )
        self.device = device
        cachedAppLinks = []
    }

    var body: some View {
        AppListView(device: device, apps: cachedAppLinks, onClick: {
            $0.lastSelected = Date.now
        })
        .onAppear {
            cachedAppLinks = apps
        }
        .onChange(of: appIdsIconsHashed) {
            cachedAppLinks = apps
        }
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
