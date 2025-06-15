import Foundation
import os
import SwiftUI

struct DevicePicker: View {
    @Environment(\.layoutDirection) var layoutDirection

    var offset: CGFloat {
        layoutDirection == .rightToLeft ? 10 : 0
    }

    let devices: [Device]
    @Binding var device: Device?
    @Binding var showingPicker: Bool
    @State var navPath: [NavigationDestination] = []
    @EnvironmentObject private var appDelegate: RoamAppDelegate

    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }

    @ViewBuilder
    var mainButton: some View {
        if #available(watchOS 11.0, *) {
            Button(action: { showingPicker.toggle() }, label: {
                Label("Devices", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
            })
            .accessibilityIdentifier("DevicePicker")
            .handGestureShortcut(.primaryAction, isEnabled: inScreenshotTestingContext())
        } else {
            // Fallback on earlier versions
            Button(action: { showingPicker.toggle() }, label: {
                Label("Devices", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
            })
            .accessibilityIdentifier("DevicePicker")
        }
    }

    var body: some View {
        mainButton
        .sheet(isPresented: $showingPicker) {
            SettingsNavigationWrapper(path: $navPath) {
                List {
                    Section("Devices") {
                        ForEach(devices) { listItemDevice in
                            Button(action: {
                                if let chosenDevice = devices.first(where: { dev in
                                    dev.id == listItemDevice.id
                                }) {
                                    Log.connection.notice("Setting last selected at")
                                    let id = chosenDevice.persistentModelID
                                    Task {
                                        do {
                                            try await RoamDataHandler().setSelectedDevice(id)
                                        } catch {
                                            Log.connection.error("Error setting selected \(error, privacy: .public)")
                                            // TODO: Set error here
                                        }
                                    }
                                }
                                showingPicker = false
                            }, label: {
                                if listItemDevice.id == device?.id {
                                    Label(listItemDevice.name, systemImage: "checkmark.circle.fill")
                                        .tag(listItemDevice as Device?)
                                } else {
                                    Label(listItemDevice.name, systemImage: "").tag(listItemDevice as Device?)
                                }
                            })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    let pid = listItemDevice.persistentModelID
                                    Task {
                                        do {
                                            try await RoamDataHandler().delete(pid)
                                        } catch {
                                            Log.connection.error("Error deleting device \(error, privacy: .public)")
                                            
                                        }
                                    }

                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .id(
                                "\(listItemDevice.name)\(listItemDevice.udn)\(listItemDevice.isOnline())\(listItemDevice.location)\(listItemDevice.lastSelectedAt ?? Date.distantPast)"
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                if let model = devices[safe: index] {
                                    let pid = model.persistentModelID
                                    Task {
                                        // TODO: Make sure the save here shows an error if device save fails, and ideally show the reason
                                        do {
                                            try await RoamDataHandler().delete(pid)
                                        } catch {
                                            Log.connection.error("Error deleting device \(error, privacy: .public)")
                                        }
                                    }
                                }
                            }
                        }

                        if devices.isEmpty {
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
    }
}
