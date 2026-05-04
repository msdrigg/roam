import Foundation
import SwiftUI
import os

struct DevicePicker: View {
    @Environment(\.layoutDirection) var layoutDirection
    @EnvironmentObject private var appDelegate: RoamWatchAppDelegate

    var offset: CGFloat {
        layoutDirection == .rightToLeft ? 10 : 0
    }

    @State var deviceListLoader = DeviceListLoader(dataHandler: RoamDataHandler.shared)
    let device: Device?
    @Binding var showingPicker: Bool
    @State var navPath: [NavigationDestination] = []
    @State private var deviceError: Error?

    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }

    @ViewBuilder
    var mainButton: some View {
        if #available(watchOS 11.0, *) {
            Button(
                action: { showingPicker.toggle() },
                label: {
                    Label("Devices", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
            )
            .accessibilityIdentifier("DevicePicker")
            .handGestureShortcut(.primaryAction, isEnabled: inScreenshotTestingContext())
        } else {
            // Fallback on earlier versions
            Button(
                action: { showingPicker.toggle() },
                label: {
                    Label("Devices", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
            )
            .accessibilityIdentifier("DevicePicker")
        }
    }

    var body: some View {
        mainButton
            .sheet(isPresented: $showingPicker) {
                SettingsNavigationWrapper(path: $navPath) {
                    List {
                        Section("Devices") {
                            ForEach(deviceListLoader.devices ?? [], id: \.self) { listItemDevice in
                                DevicePickerItem(
                                    id: listItemDevice,
                                    action: { device in
                                        Task {
                                            do {
                                                try await RoamDataHandler.shared.makePrimaryDevice(
                                                    id: device.id)
                                            } catch {
                                                Log.connection.error(
                                                    "Error setting selected \(error, privacy: .public)"
                                                )
                                                deviceError = error
                                            }
                                        }
                                        showingPicker = false
                                    }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await RoamDataHandler.shared.deleteDevice(
                                                    id: listItemDevice)
                                            } catch let error as DataHandlerError {
                                                Log.connection.error(
                                                    "Error deleting device \(error, privacy: .public)"
                                                )
                                                deviceError = error
                                            }
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    if let pid = deviceListLoader.devices?[safe: index] {
                                        Task {
                                            do {
                                                try await RoamDataHandler.shared.deleteDevice(
                                                    id: pid)
                                            } catch let error as DataHandlerError {
                                                Log.connection.error(
                                                    "Error deleting device \(error, privacy: .public)"
                                                )
                                                deviceError = error
                                            }
                                        }
                                    }
                                }
                            }

                            if deviceListLoader.devices?.isEmpty ?? true {
                                Text("No devices")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink(value: NavigationDestination.settingsDestination(.global)) {
                            Label("Settings", systemImage: "gear")
                        }
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("SettingsButton")
                    }
                }
            }
            .alertingError(message: "Device Selection Failed", error: $deviceError)
    }
}

struct DevicePickerItem: View {
    let id: String
    let action: (Device) -> Void

    @State var deviceLoader: DeviceLoader

    init(id: String, action: @escaping (Device) -> Void) {
        self.id = id
        self.action = action
        self._deviceLoader = State(
            initialValue: DeviceLoader(deviceId: id, dataHandler: RoamDataHandler.shared)
        )
    }

    var body: some View {
        Button(
            action: {
                if let device = deviceLoader.device {
                    action(device)
                }
            },
            label: {
                if let device = deviceLoader.device {
                    Label(device.name, systemImage: "checkmark.circle.fill")
                } else {
                    Label("Loading...", systemImage: "")
                }
            }
        ).tag(id)
    }
}
