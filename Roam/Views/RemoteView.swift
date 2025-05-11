import SwiftUI

struct RemoteView: View {
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject private var appDelegate: RoamAppDelegate

    private var runningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
                let dh = RoamDataHandler()
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
