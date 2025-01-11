import AppIntents
import AsyncAlgorithms
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
    var fd = FetchDescriptor(
        predicate: #Predicate {
            $0.deletedAt == nil
        },
        sortBy: [SortDescriptor(\Device.name)]
    )
    fd.relationshipKeyPathsForPrefetching = []
    fd.propertiesToFetch = [\.udn, \.location, \.name, \.lastOnlineAt, \.lastSelectedAt, \.lastScannedAt]

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
    private static nonisolated let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: RemoteView.self)
    )

    @Environment(\.scenePhase) var scenePhase
    #if !os(tvOS)
    @Environment(\.openWindow) var openWindow
    #endif

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    @Query(deviceFetchDescriptor()) private var devices: [Device]
    @Query(messageFetchDescriptor()) private var unreadMessages: [Message]

    @State private var manuallySelectedDevice: Device?
    @State private var showKeyboardEntry: Bool = false
    @State private var keyboardLeaving: Bool = false
    @State private var keyboardEntryText: String = ""
    @State var inBackground: Bool = false
    @State var buttonPresses: [RemoteButton: Int] = [:]
    @State private var headphonesModeEnabled: Bool = false
    @State private var errorTrigger: Int = 0
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
        if manuallySelectedDevice != nil && manuallySelectedDevice?.deletedAt == nil {
            manuallySelectedDevice
        } else {
            devices.filter{
                $0.deletedAt == nil
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
            }
        } else {
            SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
                RemoteViewContained()
                    .onOpenURL { incomingURL in
                        Self.logger.info("App was opened via URL: \(incomingURL)")
                        handleIncomingURL(incomingURL)
                    }
                #if os(macOS)
                    .onChange(of: appDelegate.navigationPath.messagingWindowOpenTrigger) { _, new in
                        if new != nil {
                            openWindow(id: "messages")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NSApplication.shared.activate(ignoringOtherApps: true)
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
            Self.logger.error("Getting Invalid URL path")
            return
        }
        let firstPath = path.first
        path.removeFirst()
        guard let action = path.first ?? firstPath else {
            Self.logger.warning("Getting url deep link with no action")
            return
        }
        Self.logger.info("Getting action \(action)")

        if action == "add-device" || action == "scan" {
            let queryParams = URLComponents(string: url.absoluteString)?.queryItems
            let name = queryParams?.first(where: { $0.name == "name" })?.value ?? String(localized: "New device")
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
                Self.logger.error("Trying to add device with no location")
                return
            }

            Task.detached {
                let udn = queryParams?.first(where: { $0.name == "udn" })?.value ?? "roam:newdevice-\(UUID().uuidString)"
                await DataHandler(modelContainer: getSharedModelContainer()).addOrReplaceDevice(location: location, friendlyDeviceName: name, udn: udn)
            }
        }
        if action == "feedback" {
            Self.logger.info("Attempting to open app debugging")
            appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.debugging))
        } else if action == "settings" {
            Self.logger.info("Attempting to open app settings")
            appDelegate.navigationPath.append(NavigationDestination.settingsDestination(.global))
        } else if action == "about" {
            Self.logger.info("Attempting to open about page")
            appDelegate.navigationPath.append(NavigationDestination.aboutDestination)
        } else if action == "messages" {
            Self.logger.info("Attempting to open messages page")
            appDelegate.navigationPath.append(NavigationDestination.messageDestination)
        }
    }
}

#if DEBUG
#Preview("Remote horizontal") {
    RemoteView()
        .modelContainer(previewContainer)
}
#endif
