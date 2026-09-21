#if !os(watchOS)
import SwiftUI

/// Card-styled row used in the sidebar of `DeviceSplitRoot` (iPad / macOS /
/// visionOS) and as a tap target on the iPhone home grid (`PhoneHomeView`).
///
/// Renders the device's icon, name and online indicator, with a muted
/// placeholder while the record loads.
struct DeviceSidebarCard: View {
    @State private var deviceLoader: DeviceLoader
    private let deviceId: String

    init(deviceId: String) {
        self.deviceId = deviceId
        _deviceLoader = State(initialValue: DeviceLoader(deviceId: deviceId, dataHandler: .shared))
    }

    private var device: Device? { deviceLoader.device }

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 56, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(device?.name ?? String(
                    localized: "Loading…",
                    comment: "Placeholder shown on a device card while its record loads"
                ))
                .font(.headline)
                .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        if let device {
            FallibleImage(from: device.iconURL, fallback: "tv", maxSize: 120)
        } else {
            Image(systemName: "tv")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var isOnline: Bool {
        // Read through the monitor: only the connected device gets its
        // `lastOnlineAt` refreshed.
        DeviceLivenessMonitor.shared.isOnline(device)
    }

    private var statusText: String {
        if let device {
            return getHostPortDisplay(from: device.location)
        }
        return ""
    }
}

struct DeviceSidebarFooter: View {
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    let deviceCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button {
                    appDelegate.navigationPath.showAddDevice = true
                } label: {
                    Label(
                        String(
                            localized: "Add device",
                            comment: "Footer button under the sidebar device list to add a new device"
                        ),
                        systemImage: "plus.circle"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .accessibilityIdentifier("AddDeviceButton")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())

                if deviceCount > 1 {
                    sortMenu
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            DeviceSortOrderPicker()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("SortDevicesButton")
        .accessibilityLabel(String(
            localized: "Sort devices",
            comment: "Accessibility label for the sidebar button that changes the device order"
        ))
    }
}

/// Picks the order every device list is shown in. Lives next to the lists it
/// reorders rather than in Settings. Writing through the data handler
/// republishes the device list, so open lists re-render immediately.
struct DeviceSortOrderPicker: View {
    @AppStorage(UserDefaultKeys.deviceSortOrder) private var storedOrder: String =
        DeviceSortOrder.manual.rawValue

    private var selection: Binding<DeviceSortOrder> {
        Binding {
            DeviceSortOrder(rawValue: storedOrder) ?? .manual
        } set: { newOrder in
            storedOrder = newOrder.rawValue
            Task {
                await RoamDataHandler.shared.setDeviceSortOrder(newOrder)
            }
        }
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(DeviceSortOrder.allCases) { order in
                Text(order.label).tag(order)
            }
        } label: {
            Text("Sort by", comment: "Header above the device sort options")
        }
        // Inline so the options sit under a "Sort by" header; the default
        // style nests them behind a submenu.
        .pickerStyle(.inline)
        .accessibilityIdentifier("DeviceSortOrderPicker")
    }
}

#if DEBUG
#Preview("Device Sidebar Card", traits: .fixedLayout(width: 320, height: 80)) {
    DeviceSidebarCard(deviceId: getTestingDevices()[0].id)
        .padding()
}
#endif
#endif
