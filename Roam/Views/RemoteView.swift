import AppIntents
import AVFoundation
import Intents
import os
import StoreKit
import SwiftData
import SwiftUI
import Foundation
import TipKit

@MainActor
private func deviceFetchDescriptor() -> FetchDescriptor<Device> {
    var fd = FetchDescriptor<Device>(
        predicate: globalMainDevicePredicate,
        sortBy: [SortDescriptor(\Device.name)]
    )
    fd.relationshipKeyPathsForPrefetching = []

    return fd
}

@MainActor
private func messageFetchDescriptor() -> FetchDescriptor<Message> {
    let fd = FetchDescriptor(
        predicate: #Predicate<Message> {
            !$0.viewed
        }
    )
    return fd
}

struct RemoteView: View {
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Query(deviceFetchDescriptor()) private var devices: [Device]
    @Query(messageFetchDescriptor()) private var unreadMessages: [Message]

    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
    @State private var showingAddDeviceSheet: Bool = false
    @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

    var headphonesModeDisabled: Bool {
        !(selectedDevice?.supportsDatagram ?? true)
    }

    var hideUIForKeyboardEntry: Bool {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom  == .pad {
            return false
        } else {
            return showKeyboardEntry
        }
        #else
            return false
        #endif
    }

    private var selectedDevice: Device? {
        if let manuallySelectedDevice, manuallySelectedDevice.visible {
            manuallySelectedDevice
        } else {
            devices.filter{
                $0.visible
            }.min { d1, d2 in
                (d1.lastSelectedAt?.timeIntervalSince1970 ?? 0) > (d2.lastSelectedAt?.timeIntervalSince1970 ?? 0)
            }
        }
    }

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @ScaledMetric var buttonRadius = globalButtonRadius

    private struct IsHorizontalKey: PreferenceKey {
        static let defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    private struct IsSmallWidth: PreferenceKey {
        static let  defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = nextValue()
        }
    }

    var body: some View {
        if runningInPreview {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
                RemoteViewContained()
                    .sheet(isPresented: $showingAddDeviceSheet) {
                        AddDeviceFlow()
                    }
            }
        } else {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
                RemoteViewContained()
                    .sheet(isPresented: $showingAddDeviceSheet) {
                        AddDeviceFlow()
                    }
                    .onOpenURL { incomingURL in
                        Log.lifecycle.notice("App was opened via URL: \(incomingURL, privacy: .public)")
                        handleIncomingURL(incomingURL)
                    }
                #if os(macOS)
                    .onChange(of: appDelegate.navigationPath.messagingWindowOpenTrigger) { _, new in
                        if new != nil {
                            openWindow(id: "messages")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NSApp.forceFront("messages")
                            }
                        }
                    }
                #endif
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.host == "roam.msd3.io" else {
            return
        }

        var path = url.pathComponents
        path.removeFirst()
        guard let dlpath = path.first, dlpath == "deep-link" else {
            Log.lifecycle.error("Getting Invalid URL path")
            return
        }
        let firstPath = path.first
        path.removeFirst()
        guard let action = path.first ?? firstPath else {
            Log.lifecycle.warning("Getting url deep link with no action")
            return
        }
        Log.lifecycle.notice("Getting action \(action, privacy: .public)")

        if action == "add-device" || action == "scan" {
            let queryParams = URLComponents(string: url.absoluteString)?.queryItems
            // Get location param as location=IP or p=IPV4Hex
            guard let location = queryParams?.first(where: { $0.name == "location" })?.value ??
                queryParams?.first(where: { $0.name == "p" })?.value.flatMap({ hex in
                    let ipComponents = stride(from: 0, to: hex.count, by: 2).compactMap { index -> UInt8? in
                        let start = hex.index(hex.startIndex, offsetBy: index)
                        let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                        return UInt8(hex[start ..< end], radix: 16)
                    }
                    guard ipComponents.count == 4 else { return nil }
                    return ipComponents.map(String.init).joined(separator: ".")
                })
            else {
                Log.lifecycle.error("Trying to add device with no location")
                return
            }

            Task {
                let dh = DataHandler()
                if let pid = await dh.addOrReplaceDevice(location: location) {
                    Log.lifecycle.notice("Added device with PID \(pid.described(), privacy: .public)")
                    await dh.setSelectedDevice(pid)
                }
            }
        }
        if action == "settings" {
            Log.lifecycle.notice("Attempting to open app settings")
            appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.global))
        } else if action == "about" {
            Log.lifecycle.notice("Attempting to open about page")
            appDelegate.navigationPath.append(NavigationDestination.aboutDestination)
        } else if action == "messages" {
            Log.lifecycle.notice("Attempting to open messages page")
            appDelegate.navigationPath.append(NavigationDestination.messageDestination)
        }
    }
}
