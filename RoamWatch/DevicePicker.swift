//
//  DevicePicker.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import os
import SwiftUI

struct DevicePicker: View {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )

    @Environment(\.layoutDirection) var layoutDirection

    var offset: CGFloat {
        layoutDirection == .rightToLeft ? 10 : 0
    }

    let devices: [Device]
    @Binding var device: Device?
    @Binding var showingPicker: Bool
    @State var navPath: [NavigationDestination] = []

    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }

    var mainButton: some View {
        if #available(watchOS 11.0, *) {
            return AnyView(Button(action: { showingPicker.toggle() }, label: {
                Label("Devices", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("DevicePickerLabel")
            })
            .handGestureShortcut(.primaryAction, isEnabled: inScreenshotTestingContext()))
        } else {
            // Fallback on earlier versions
            return AnyView(Button(action: { showingPicker.toggle() }, label: {
                Label("Devices", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("DevicePickerLabel")
            }))
        }
    }

    var body: some View {
        mainButton
        .accessibilityIdentifier("DevicePicker")
        .sheet(isPresented: $showingPicker) {
            SettingsNavigationWrapper(path: $navPath) {
                List {
                    Section("Devices") {
                        ForEach(devices) { listItemDevice in
                            Button(action: {
                                if let chosenDevice = devices.first(where: { dev in
                                    dev.id == listItemDevice.id
                                }) {
                                    Self.logger.debug("Setting last selected at")
                                    let id = chosenDevice.persistentModelID
                                    Task.detached {
                                        await DataHandler(modelContainer: getSharedModelContainer()).setSelectedDevice(id)
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
                                    Task.detached {
                                        do {
                                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                                        } catch {
                                            Self.logger.error("Error deleting device \(error, privacy: .public)")
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
                                    Task.detached {
                                        do {
                                            try await DataHandler(modelContainer: getSharedModelContainer()).delete(pid)
                                        } catch {
                                            Self.logger.error("Error deleting device \(error, privacy: .public)")
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
