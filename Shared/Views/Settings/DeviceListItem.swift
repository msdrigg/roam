import SwiftUI

struct DeviceListItem: View {
    @Bindable var device: Device
    var idx: Int

    @Environment(\.uuidUpdater) private var updater

    var body: some View {
        NavigationLink(value: NavigationDestination.deviceSettingsDestination(device.persistentModelID)) {
            HStack(alignment: .center) {
                VStack(alignment: .center) {
                    DataImage(from: device.deviceIcon, fallback: "tv")
                        .frame(maxHeight: 60)
                        .padding(.trailing, 12)
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
        .accessibilityIdentifier("DeviceItem_\(idx)")
#if !os(watchOS)
        .contextMenu {
            Button(role: .destructive) {
                let pid = device.persistentModelID
                Task.detached {
                    do {
                        try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                        Log.userInteraction
                            .notice(
                                "Deleted device with id \(String(describing: pid), privacy: .public)"
                            )
                        DispatchQueue.main.async {
                            self.updater?.update()
                        }
                    } catch {
                        Log.userInteraction.error("Error deleting device \(error, privacy: .public)")
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
    }
}

#if DEBUG
#Preview(
    "Device List Item",
    traits: .fixedLayout(width: 800, height: 700)
) {
    Form {
        DeviceListItem(device: getTestingDevices()[0], idx: 0)
            .padding()
    }
    .formStyle(.grouped)
}
#endif
