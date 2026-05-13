#if !os(watchOS)
import SwiftUI

/// Card-styled row used in the sidebar of `DeviceSplitRoot` (iPad / macOS /
/// visionOS) and as a tap target on the iPhone home grid (`PhoneHomeView`).
///
/// Renders the device's icon, name, and a small online-status indicator. While
/// the device record is still loading it shows a muted placeholder so the
/// sidebar can render immediately rather than wait for a network round-trip.
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
        device?.isOnline() ?? false || inScreenshotTestingContext()
    }

    private var statusText: String {
        if let device {
            return getHostPortDisplay(from: device.location)
        }
        return ""
    }
}

#if DEBUG
#Preview("Device Sidebar Card", traits: .fixedLayout(width: 320, height: 80)) {
    DeviceSidebarCard(deviceId: getTestingDevices()[0].id)
        .padding()
}
#endif
#endif
