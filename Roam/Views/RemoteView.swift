import SwiftUI

struct RemoteView: View {
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject private var appDelegate: RoamAppDelegate
    @State private var deviceError: Error?

    var body: some View {
        #if os(macOS)
        SettingsNavigationWrapper(path: $appDelegate.navigationPath.navigationPath) {
            RemoteViewContained()
                .onChange(of: appDelegate.navigationPath.messagingWindowOpenTrigger) { _, new in
                    if new != nil {
                        openWindow(id: "messages")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApp.forceFront("messages")
                        }
                    }
                }
        }
        .alertingError(message: "Failed to Add Device", error: $deviceError)
        #elseif os(watchOS)
        EmptyView()
        #else
        RemoteRoot()
            .onOpenURL { incomingURL in
                Log.lifecycle.notice("App was opened via URL: \(incomingURL, privacy: .public)")
                handleIncomingURL(incomingURL)
            }
            .alertingError(message: "Failed to Add Device", error: $deviceError)
        #endif
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

        if action == "settings" {
            Log.lifecycle.notice("Attempting to open app settings")
            appDelegate.navigationPath.append(.settingsDestination(.global))
        } else if action == "about" {
            Log.lifecycle.notice("Attempting to open about page")
            appDelegate.navigationPath.openAbout()
        } else if action == "messages" {
            Log.lifecycle.notice("Attempting to open messages page")
            appDelegate.navigationPath.openMessages()
        }
    }
}
