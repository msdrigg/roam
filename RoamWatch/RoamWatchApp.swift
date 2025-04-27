import os.log
import SwiftData
import SwiftUI
import TipKit

@main
struct RoamWatch: App {
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: tipsAppGroup))
        ])

        Log.lifecycle.notice("Getting WatchConnectivity \(String(describing: WatchConnectivity.shared), privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            WatchAppView()
        }
        .modelContainer(sharedModelContainer)
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

private let deviceFetchDescriptor: FetchDescriptor<Device> = {
    var fd = FetchDescriptor<Device>(
        predicate: #Predicate<Device> { d in
            d.deletedAt == nil && d.hiddenAt == nil
        },
        sortBy: [SortDescriptor(\Device.name)]
    )
    fd.propertiesToFetch = [
        \Device.udn, \Device.location, \Device.name,
         \Device.lastOnlineAt, \Device.lastSelectedAt,
         \Device.lastScannedAt
    ]

    return fd
}()

struct WatchAppView: View {
    @State private var scanningActor: DeviceDiscoveryActor!

    @Query(deviceFetchDescriptor) private var devices: [Device]
    @State private var manuallySelectedDevice: Device?
    @State private var showDeviceList: Bool = false

    @AppStorage(UserDefaultKeys.shouldScanIPRangeAutomatically) private var scanIpAutomatically: Bool = true

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDevice: Device? {
        manuallySelectedDevice ?? devices.min { d1, d2 in
            (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
        }
    }

    @State var navPath: NavigationManager = NavigationManager()

    @MainActor
    var mainBody: some View {
        SettingsNavigationWrapper(path: $navPath.navigationPath) {
            TabView {
                if selectedDevice == nil {
                    VStack {
                        Button(action: {
                            navPath.append(NavigationDestination.settingsDestination(.global))
                        }, label: {
                            Label(String(localized: "Setup a device to get started :)", comment: "Label on a button to open the device setup page"), systemImage: "gear")
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
                scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer(), updater: { })
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
                        try! await DataHandler(modelContainer: getSharedModelContainer()).loadTestData()
                    } else if usingTestingDataContainer() {
                        // swiftlint:disable:next force_try
                        try! await DataHandler(modelContainer: getSharedModelContainer()).clearData()
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
                            let handler = DataHandler(modelContainer: getSharedModelContainer())
                            await handler.refreshDevice(client: WatchOSRefreshClient(id: selectedDevice.persistentModelID, location: selectedDevice.location))
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
            appLinkPairs.insert("\(app.id);\(app.icon != nil)")
        }

        var hasher = Hasher()
        hasher.combine(appLinkPairs)
        return hasher.finalize()
    }

    init(device: DeviceAppEntity) {
        let pid = device.udn

        _apps = Query(
            filter: #Predicate<AppLink> {
                $0.deviceUid == pid
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
    WatchAppView()
        .modelContainer(getTestingContainer())
}
#endif
