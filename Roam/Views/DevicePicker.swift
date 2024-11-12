import Foundation
import os
import SwiftUI

#if os(tvOS)
    let globalBaselineOffset: CGFloat = 4
    let globalCircleIconSize: CGFloat = 16
#else
    let globalBaselineOffset: CGFloat = 2
    let globalCircleIconSize: CGFloat = 10
#endif

struct DevicePicker: View {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )

    @ScaledMetric var baselineOffset = globalBaselineOffset
    @ScaledMetric var circleIconSize = globalCircleIconSize

    @Environment(\.openURL) private var openURL
    @Environment(\.createDataHandler) private var createDataHandler
    @Environment(\.uuidUpdater) private var updater
#if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
#endif

    let devices: [Device]
    var device: Binding<Device?>

    let showScanning: Bool
    let ecpSessionState: ECPSessionState?

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var currentDate: Date = .now

    var deviceStatusColor: Color {
        return if let ecpSessionState {
            switch ecpSessionState.status {
            case .connected:
                    .green
            case let .disconnected(date):
                if currentDate.timeIntervalSince(date) < 1 {
                    .green
                } else {
                    .secondary
                }
            case .connecting:
                .secondary
            }
        } else {
            device.wrappedValue?.isOnline() ?? false ? .green : .secondary
        }
    }

    var showSpinning: Bool {
        return if let ecpSessionState {
            switch ecpSessionState.status {
            case .connected:
                false
            case let .connecting(date):
                if currentDate.timeIntervalSince(date) < 5 {
                    true
                } else {
                    false
                }
            case .disconnected:
                false
            }
        } else {
            false
        }
    }

    init(devices: [Device], device: Binding<Device?>, ecpSessionState: ECPSessionState? = nil, showScanning: Bool = false) {
        self.devices = devices
        self.device = device
        self.showScanning = showScanning
        self.ecpSessionState = ecpSessionState
    }

    var body: some View {
        Menu {
            if !devices.isEmpty {
                Picker("Device", selection: Binding<Device?>(
                    get: {
                        device.wrappedValue
                    },
                    set: {
                        device.wrappedValue = $0
                        if let pid = $0?.persistentModelID {
                            Task.detached {
                                try? await Task.sleep(duration: 0.5)
                                await createDataHandler()?.setSelectedDevice(pid)
                            }
                        }
                    }
                )) {
                    ForEach(devices) { device in
                        Text(device.name)
                            .lineLimit(1)
                            .tag(device as Device?)
                    }
                }.pickerStyle(.inline)
            } else {
                Text("No devices")
            }

            Divider()
            #if os(macOS)
                Button(action: {
                    openSettings()
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }, label: {
                    Label("Settings", systemImage: "gear")
                        .labelStyle(.titleAndIcon)
                })
            #else
                NavigationLink(value: NavigationDestination.settingsDestination(.global)) {
                    Label("Settings", systemImage: "gear")
                }
                .labelStyle(.titleAndIcon)
            #endif
        } label: {
            Group {
                if let device = device.wrappedValue {
                    if showSpinning {
                        Label(device.name, systemImage: "rays")
                            .labelStyle(DevicePickerLabelStyle(circleIconSize: circleIconSize))
                            .foregroundColor(deviceStatusColor)
                            .symbolEffect(.variableColor)
                    } else {
                        Label(device.name, systemImage: "circle.fill")
                            .labelStyle(DevicePickerLabelStyle(circleIconSize: circleIconSize))
                            .foregroundColor(deviceStatusColor)
                    }
                } else {
                    if showScanning {
                        Label("Scanning for devices", systemImage: "rays")
                            .labelStyle(.titleAndIcon)
                            .symbolEffect(.variableColor)
                    } else {
                        Text("No devices")
                    }
                }
            }
            #if os(macOS)
                .multilineTextAlignment(.center)
            #else
                .multilineTextAlignment(.trailing)
            #endif
                .lineLimit(1)
                .truncationMode(.tail)
            #if !os(macOS)
                .frame(maxWidth: 300)
                .fixedSize()
            #endif
            #if os(visionOS)
                .font(.headline)
            #else
                .font(.body)
            #endif
        }
        #if !os(macOS)
        .menuStyle(.button)
        .buttonStyle(.plain)
        #endif
        .animation(nil, value: UUID())
        .onReceive(timer) { _ in
            currentDate = .now
        }
        .id(updater?.uuid.uuidString ?? "--")
    }
}

struct DevicePickerLabelStyle: LabelStyle {
    let circleIconSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon
                .font(.system(size: circleIconSize))

            configuration.title
                .font(.body)
                .padding(.trailing, 4)
            #if !os(macOS)
                .foregroundColor(.accentColor)
            #else
                .foregroundColor(.primary)
            #endif
        }
    }
}
