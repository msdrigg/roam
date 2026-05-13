import Foundation
import SwiftUI
import os

let globalBaselineOffset: CGFloat = 2
let globalCircleIconSize: CGFloat = 10

struct DevicePicker: View {
    @ScaledMetric var baselineOffset = globalBaselineOffset
    @ScaledMetric var circleIconSize = globalCircleIconSize

    @Environment(\.openURL) private var openURL
    #if !os(macOS)
        @EnvironmentObject private var appDelegate: RoamAppDelegate
    #endif
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
        @Environment(\.openWindow) private var openWindow
    #endif

    var device: Device?

    let showScanning: Bool
    let ecpSessionState: ECPMonitor?

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var currentDate: Date = .now
    @State private var deviceError: Error?
    @State private var deviceListLoader = DeviceListLoader(dataHandler: .shared)

    var deviceStatusColor: Color {
        if inScreenshotTestingContext() {
            return .green
        }
        return if let ecpSessionState {
            switch ecpSessionState.status {
            case .connected:
                .green
            case .disconnected(let date):
                if currentDate.timeIntervalSince(date) < 0.2 {
                    .green
                } else {
                    .secondary
                }
            case .connecting:
                .secondary
            }
        } else {
            device?.isOnline() ?? false ? .green : .secondary
        }
    }

    var showSpinning: Bool {
        return if let ecpSessionState, !inScreenshotTestingContext() {
            switch ecpSessionState.status {
            case .connected:
                false
            case .connecting(let date):
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

    init(device: Device?, ecpSessionState: ECPMonitor? = nil, showScanning: Bool = false) {
        self.device = device
        self.showScanning = showScanning
        self.ecpSessionState = ecpSessionState
    }

    var body: some View {
        HStack(spacing: 8) {
            if !(deviceListLoader.devices ?? []).isEmpty {
                Picker(
                    "Device",
                    selection: Binding<String?>(
                        get: {
                            device?.id
                        },
                        set: {
                            if let pid = $0 {
                                Task {
                                    do {
                                        try await RoamDataHandler.shared.makePrimaryDevice(id: pid)
                                    } catch {
                                        Log.userInteraction.error(
                                            "Error setting selected device \(error, privacy: .public)"
                                        )
                                        deviceError = error
                                    }
                                }
                            }
                        }
                    )
                ) {
                    ForEach(deviceListLoader.devices ?? [], id: \.self) { device in
                        DevicePickerItem(id: device)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: devicePickerMaxWidth)
                .accessibilityIdentifier("DevicePicker")
            } else {
                Text("No devices")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: devicePickerMaxWidth)
                    .accessibilityIdentifier("DevicePicker")
            }

            #if os(macOS)
                Button(
                    action: {
                        openSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApp.forceFront("com_apple_SwiftUI_Settings_window")
                        }
                    },
                    label: {
                        Label("Settings", systemImage: "gear")
                            .labelStyle(.iconOnly)
                    }
                )
                .buttonStyle(PaddedBorderlessButtonStyle())
                .accessibilityIdentifier("SettingsButton")
            #else
                Button {
                    appDelegate.navigationPath.append(.settingsDestination(.global))
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(PaddedBorderlessButtonStyle())
                .accessibilityIdentifier("SettingsButton")
            #endif
        }
        .fixedSize(horizontal: false, vertical: true)
        //        Menu {
        //        } label: {
        //            Group {
        //                if let device = device {
        //                    if showSpinning {
        //                        Label(device.name, systemImage: "rays")
        //                            .labelStyle(DevicePickerLabelStyle(circleIconSize: circleIconSize))
        //                            .foregroundColor(deviceStatusColor)
        //                            .symbolEffect(.variableColor)
        //                    } else {
        //                        Label(device.name, systemImage: "circle.fill")
        //                            .labelStyle(DevicePickerLabelStyle(circleIconSize: circleIconSize))
        //                            .foregroundColor(deviceStatusColor)
        //                    }
        //                } else {
        //                    if showScanning {
        //                        Label("Scanning for devices", systemImage: "rays")
        //                            .labelStyle(.titleAndIcon)
        //                            .symbolEffect(.variableColor)
        //                    } else {
        //                        Text("No devices")
        //                    }
        //                }
        //            }
        //            #if os(macOS)
        //                .multilineTextAlignment(.center)
        //            #else
        //                .multilineTextAlignment(.trailing)
        //            #endif
        //                .lineLimit(1)
        //                .truncationMode(.tail)
        //            #if os(iOS)
        //                .frame(maxWidth: 300)
        //                .fixedSize()
        //            #elseif os(visionOS)
        //                .frame(maxWidth: 250)
        //                .fixedSize()
        //            #endif
        //            #if os(visionOS)
        //                .font(.headline)
        //            #else
        //                .font(.body)
        //            #endif
        //        }
        //        #if os(iOS)
        //        .menuStyle(.button)
        //        #endif
        //        .accessibilityIdentifier("DevicePicker")
        //        .animation(nil, value: UUID())
        //        .onReceive(timer) { _ in
        //            currentDate = .now
        //        }
        //        .alertingError(message: "Failed to Select Device", error: $deviceError)
    }

    private var devicePickerMaxWidth: CGFloat {
        #if os(macOS)
            return 185
        #else
            return .infinity
        #endif
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
                #if !os(macOS) && !os(visionOS)
                    .foregroundColor(.accentColor)
                #else
                    .foregroundColor(.primary)
                #endif
        }
    }
}

private struct DevicePickerItem: View {
    @State private var deviceLoader: DeviceLoader

    let id: String

    init(id: String) {
        self.id = id
        self._deviceLoader = State(
            initialValue: DeviceLoader(deviceId: self.id, dataHandler: .shared))
    }

    var name: String {
        deviceLoader.device?.name ?? "Loading..."
    }

    var body: some View {
        Text(name)
            .lineLimit(1)
            .truncationMode(.tail)
            .tag(id)
    }
}
