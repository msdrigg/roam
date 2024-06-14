import os.log
import SwiftData
import SwiftUI

@main
struct RoamWatch: App {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RoamWatch.self)
    )
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
        Self.logger.info("Getting WatchConnectivity \(String(describing: WatchConnectivity.shared))")
    }

    var body: some Scene {
        WindowGroup {
            WatchAppView()
        }
        .modelContainer(sharedModelContainer)
        .environment(\.createDataHandler, dataHandlerCreator())
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
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name, order: .reverse)]
    )
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]

    return fd
}()

struct WatchAppView: View {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WatchAppView.self)
    )

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

    @State var navPath: [NavigationDestination] = []

    @MainActor
    var mainBody: some View {
        SettingsNavigationWrapper(path: $navPath) {
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
            .navigationTitle(selectedDevice?.name ?? "No device")
            .toolbar(id: "watch") {
                ToolbarItem(id: "device-picker", placement: .topBarLeading) {
                    DevicePicker(
                        devices: devices,
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
                scanningActor = DeviceDiscoveryActor(modelContainer: getSharedModelContainer())
            }
        }
    }

    var body: some View {
        if runningInPreview {
            mainBody
        } else {
            mainBody
                .task(id: selectedDevice?.persistentModelID, priority: .medium) {
                    if let devId = selectedDevice?.persistentModelID {
                        await scanningActor.refreshSelectedDeviceContinually(id: devId)
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
            filter: #Predicate {
                pid != nil && $0.deviceUid == pid
            },
            sort: \.lastSelected,
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
        .modelContainer(testingContainer)
        .environment(\.createDataHandler, dataHandlerCreator())

}
#endif
