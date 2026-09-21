import Foundation
import OSLog
import SwiftUI
import UserNotifications

#if os(macOS)
import AppKit

final class RoamAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var navigationPath: NavigationManager
    @Published var ecpMonitor: ECPMonitor
    @Published var networkMonitor: NetworkMonitor

    var delegates: [String: AnyObject] = [:]

    @MainActor
    override init() {
        self.navigationPath = NavigationManager()
        self.ecpMonitor = ECPMonitor()
        self.networkMonitor = NetworkMonitor()
        super.init()
        networkMonitor.appDelegate = self
        UNUserNotificationCenter.current().delegate = self
        Log.lifecycle.notice("Setting Notifications delegate to self")
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Honor `-OpenMenuBarExtra` (see Roam/ScreenshotCapture.swift):
        // forces showMenuBar on so SwiftUI installs the MenuBarExtra,
        // clicks the status item to open the popover, and writes the
        // resulting icon + popover screen frames to
        // `-MenuBarExtraReportPath` for the Tart-driven screenshot
        // orchestrator. No-op when neither launch arg is set.
        MacScreenshotCapture.scheduleIfRequested(appDelegate: self)

        let hasSentFirstMessage = UserDefaults.standard.bool(forKey: UserDefaultKeys.hasSentFirstMessage)
        self.networkMonitor.startMonitoring()

        if hasSentFirstMessage {
            UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: UserDefaultKeys.lastApnsRequestTime)
            requestNotificationPermission()
        }

        if UserDefaults.standard.string(forKey: UserDefaultKeys.firstInstallVersion) == nil {
            if let version = Bundle.main.infoDictionary?["CURRENT_PROJECT_VERSION"] as? String {
                Log.lifecycle.notice("Setting first install version to \(version, privacy: .public)")
                UserDefaults.standard.set(version, forKey: UserDefaultKeys.firstInstallVersion)
            }
        }

        if initialInstallationAfter("20250412.5345670.3") {
            if UserDefaults.standard.value(forKey: UserDefaultKeys.alreadyResetHideShortcut) == nil {
                Log.lifecycle.info("Setting hidden shortcut to be cmd+shift+h")
                CustomKeyboardShortcut(title: .home, key: KeyEquivalent("h"), modifiers: [.command, .shift]).persist()
                UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.alreadyResetHideShortcut)
            }
        }

        Task {
            do {
                let selectedDevice = await RoamDataHandler.shared.requestPrimaryDevice()

                if let selectedDevice, ecpMonitor.ecpClient == nil {
                    ecpMonitor.setDevice(selectedDevice)
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !UserDefaults.standard.bool(forKey: UserDefaultKeys.showMenuBar)
    }

    func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data -> String in
            String(format: "%02.2hhx", data)
        }
        let token = tokenParts.joined()
        Log.notifications.notice("Device Token: \(token, privacy: .public)")

        Task {
            do {
                try await uploadApnsToken(token)
            } catch {
                Log.notifications.error("Error sending apns token to server \(error, privacy: .public)")
            }
            UserDefaults.standard.set(true, forKey: UserDefaultKeys.hasSentFirstMessage)
        }
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Log.notifications.notice("Received remote notification \(userInfo, privacy: .public)")

        refreshMessages()
        if let aps = userInfo["aps"] as? [String: Any],
           let alert = aps["alert"] as? String,
           alert == "TYPING" {
            Log.notifications.notice("Received TYPING notification")
            handleTypingNotification()
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Log.notifications.notice("didReceive notification. Showing Messages...")
        refreshMessages()
        let navigationPath = self.navigationPath
        DispatchQueue.main.async {
            navigationPath.messagingWindowOpenTrigger = UUID()
        }
        completionHandler()
    }

    func refreshMessages() {
        Task {
            await RoamDataHandler.shared.refreshMessagesIfExpectingNewMessages()
        }
    }

    func handleTypingNotification() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: UserDefaultKeys.lastSupportTypingTime)
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Log.notifications.notice("WillPresent notification. Refreshing messages...")
        refreshMessages()
        completionHandler(.badge)
    }

    func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.notifications.error("Failed to register with Error \(error, privacy: .public)")
    }
}

extension NSApplication {
    /// Brings the window with `id` to the front on the next runloop turn.
    ///
    /// The hop matters. Every caller is a SwiftUI action (`onAppear`, a button,
    /// a hotkey handler), so a synchronous body would run inside
    /// `Update.dispatchActions`, still nested in the update pass that queued it.
    /// `makeKeyAndOrderFront` posts `NSWindowDidOrderOnScreen` from there,
    /// SwiftUI turns that into a scene-phase change, and
    /// `AppGraph.graphDidChange` re-enters the update it is already inside.
    /// Under launch-time window restoration that cycle does not settle: each
    /// level re-evaluates the scene bodies, and the main thread runs off the end
    /// of its stack (`EXC_BAD_ACCESS` in Stack Guard, roam 1.51 on macOS 26.5).
    ///
    /// Deferring lets the in-flight update finish first, so the notification
    /// lands on a quiet graph. It also resolves the window later, which matters
    /// for the callers that pair this with `openWindow(id:)` -- the new window is
    /// not in `self.windows` yet at the moment they call.
    func forceFront(_ id: String) {
        DispatchQueue.main.async {
            let window: NSWindow? = self.windows.first {
                $0.identifier == NSUserInterfaceItemIdentifier(rawValue: id)
            }

            Log.lifecycle.notice("Making window front \(id, privacy: .public), \(window?.title ?? "nil", privacy: .public)")
            NSApplication.shared.activate(ignoringOtherApps: true)

            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    /// Applies `policy` on the next runloop turn, and only if it differs from
    /// the policy already in force.
    ///
    /// Same hazard as `forceFront`, by a longer route. Switching between
    /// `.regular` and `.accessory` adds or removes the app from the Dock and
    /// rebuilds the menu bar, and AppKit orders windows on and off screen as it
    /// does so. Those orderings post `NSWindowDidOrderOnScreen` synchronously,
    /// which SwiftUI turns into a scene-phase change -- so a synchronous call
    /// from a scene's `onAppear` / `onDisappear` runs inside
    /// `Update.dispatchActions` and re-enters the update pass that queued it.
    ///
    /// Coalescing matters as much as deferring. All five macOS window scenes
    /// ask on appear and again on disappear, so one launch-time restore issues
    /// a burst of contradictory requests; only the last one describes the state
    /// the app actually settled into. Collapsing them to a single call at the
    /// end of the turn also means the common case -- the policy is already what
    /// the caller wants -- costs nothing and touches no window.
    @MainActor
    func setActivationPolicyDeferred(_ policy: ActivationPolicy) {
        ActivationPolicyCoalescer.pending = policy
        guard !ActivationPolicyCoalescer.scheduled else { return }
        ActivationPolicyCoalescer.scheduled = true

        DispatchQueue.main.async {
            ActivationPolicyCoalescer.scheduled = false
            guard let wanted = ActivationPolicyCoalescer.pending else { return }
            ActivationPolicyCoalescer.pending = nil

            guard self.activationPolicy() != wanted else { return }

            Log.lifecycle.notice(
                "Setting activation policy to \(String(describing: wanted), privacy: .public)")
            self.setActivationPolicy(wanted)
        }
    }
}

/// Coalescing state for `NSApplication.setActivationPolicyDeferred`. Lives
/// outside the extension because extensions cannot add stored properties.
@MainActor
private enum ActivationPolicyCoalescer {
    static var pending: NSApplication.ActivationPolicy?
    static var scheduled = false
}
#else
    import UIKit
    import Combine

    final class UserDefaultsPublisher: Sendable {
        static let shared = UserDefaultsPublisher()

        func publisher<T: Decodable>(for key: String) -> AnyPublisher<T, Never> {
            return NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
                .map { _ in
                    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
                    return try? PropertyListDecoder().decode(T.self, from: data)
                }
                .compactMap { $0 }
                .eraseToAnyPublisher()
        }
    }

    extension EventModifiers {
        var uiKeyModifierFlagsRepresentation: UIKeyModifierFlags {
            var flags = UIKeyModifierFlags()
            if self.contains(.shift) {
                flags.insert(.shift)
            }
            if self.contains(.control) {
                flags.insert(.control)
            }
            if self.contains(.option) {
                flags.insert(.alternate)
            }
            if self.contains(.command) {
                flags.insert(.command)
            }
            if self.contains(.capsLock) {
                flags.insert(.alphaShift)
            }
            return flags
        }
    }

    extension UIViewController {
        func findFirstResponder() -> UIResponder? {
            if self.isFirstResponder {
                return self
            }
            for view in self.view.subviews {
                if let responder = view.findFirstResponder() {
                    return responder
                }
            }
            return nil
        }
    }

    extension UIView {
        func findFirstResponder() -> UIResponder? {
            if self.isFirstResponder {
                return self
            }
            if let next = self.next, next.isFirstResponder {
                return next
            }

            for subview in self.subviews {
                if let responder = subview.findFirstResponder() {
                    return responder
                }
            }
            return nil
        }

        func findFocused() -> UIView? {
            if self.isFocused{
                return self
            }

            for subview in self.subviews {
                if let responder = subview.findFocused() {
                    return responder
                }
            }
            return nil
        }
    }

    final class RoamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject, Sendable {
        @Published var navigationPath: NavigationManager
        @Published var ecpMonitor: ECPMonitor
        @Published var networkMonitor: NetworkMonitor
        let discoveryCoordinator: DiscoveryCoordinator
        let timedMute: TimedMuteController

        override init() {
            self.navigationPath = NavigationManager()
            let ecpMonitor = ECPMonitor()
            self.ecpMonitor = ecpMonitor
            self.networkMonitor = NetworkMonitor()
            self.discoveryCoordinator = DiscoveryCoordinator()
            let timedMute = TimedMuteController(driver: .live(ecpMonitor: ecpMonitor))
            self.timedMute = timedMute
            super.init()
            UNUserNotificationCenter.current().delegate = self
            #if os(iOS)
            TimedMuteActivityBridge.unmute = { await timedMute.handleNotificationResponse() }
            #endif
        }

        func application(
            _ application: UIApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) {
            Log.notifications.notice("Received remote notifications \(userInfo, privacy: .public)")
            refreshMessages(fetchCompletionHandler: completionHandler)
            if let aps = userInfo["aps"] as? [String: Any],
               let alert = aps["alert"] as? String,
               alert == "TYPING" {
                Log.notifications.notice("Received TYPING notification")
                handleTypingNotification()
            }

        }

        func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
            Log.lifecycle.warning("Received memory warning")
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            let tokenParts = deviceToken.map { data -> String in
                String(format: "%02.2hhx", data)
            }
            let token = tokenParts.joined()
            Log.notifications.notice("Device Token: \(token, privacy: .public)")

            Task {
                do {
                    try await uploadApnsToken(token)
                } catch {
                    Log.notifications.error("Error sending apns token to server \(error, privacy: .public)")
                }
                UserDefaults.standard.set(true, forKey: UserDefaultKeys.hasSentFirstMessage)
            }
        }

        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            if response.notification.request.content.categoryIdentifier == TimedMuteController.notificationCategory {
                Log.notifications.notice("didReceive timed mute notification \(response.actionIdentifier, privacy: .public)")
                nonisolated(unsafe) let completionHandler = completionHandler
                Task { @MainActor in
                    await self.timedMute.handleNotificationResponse()
                    completionHandler()
                }
                return
            }
            Log.notifications.notice("didReceive notification. Showing Messages...")
            DispatchQueue.main.async {
                self.refreshMessages()
                self.navigationPath.openMessages()
            }

            completionHandler()
        }

        func refreshMessages(fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)? = nil) {
            Task {
                let refreshResult = await RoamDataHandler.shared.refreshMessagesIfExpectingNewMessages()
                if refreshResult > 0 {
                    completionHandler?(.newData)
                } else {
                    completionHandler?(.noData)
                }
            }
        }

        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            // In the foreground the remote view already shows the timer.
            if notification.request.content.categoryIdentifier == TimedMuteController.notificationCategory {
                completionHandler([])
                return
            }
            Log.notifications.notice("willPresent notification. Refreshing...")
            DispatchQueue.main.async {
                self.refreshMessages()
            }
            completionHandler(.badge)
        }

        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            let launchState: String = {
                switch application.applicationState {
                case .active: return "active"
                case .inactive: return "inactive"
                case .background: return "background"
                @unknown default: return "unknown"
                }
            }()
            let reasons = (launchOptions ?? [:]).keys.map(\.rawValue).sorted().joined(separator: ",")
            FileLog.recordLaunchState(reasons.isEmpty ? launchState : "\(launchState) options=\(reasons)")

            self.networkMonitor.startMonitoring()
            self.timedMute.resumeIfNeeded()
            let hasSentFirstMessage = UserDefaults.standard.bool(forKey: UserDefaultKeys.hasSentFirstMessage)
            if hasSentFirstMessage {
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: UserDefaultKeys.lastApnsRequestTime)
                requestNotificationPermission()
            }

            if UserDefaults.standard.string(forKey: UserDefaultKeys.firstInstallVersion) == nil {
                if let version = Bundle.main.infoDictionary?["CURRENT_PROJECT_VERSION"] as? String {
                    UserDefaults.standard.set(version, forKey: UserDefaultKeys.firstInstallVersion)
                }
            }

            if initialInstallationAfter("20250412.5345670.3") {
                if UserDefaults.standard.string(forKey: UserDefaultKeys.alreadyResetHideShortcut) == nil {
                    Log.lifecycle.info("Setting hidden shortcut to be cmd+shift+h")
                    CustomKeyboardShortcut(title: .home, key: KeyEquivalent("h"), modifiers: [.command, .shift]).persist()
                    UserDefaults.standard.setValue(true, forKey: UserDefaultKeys.alreadyResetHideShortcut)
                }
            }

            Task {
                let selectedDevice = await RoamDataHandler.shared.requestPrimaryDevice()

                if let selectedDevice, ecpMonitor.ecpClient == nil {
                    ecpMonitor.setDevice(selectedDevice)
                }
            }

            return true
        }

        func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            // Migrations lock files in the shared app-group container. Acquire
            // suspension protection before opening them, after UIApplicationMain
            // creates UIApplication. A task requested in RoamApp.init is invalid.
            let dontKillAssertion = QRunInBackgroundAssertion(name: "roam-launch-database-init")
            defer { dontKillAssertion.release() }
            Log.lifecycle.notice(
                "Opening database, launch guard \(dontKillAssertion.isReleased() ? "not held" : "held", privacy: .public)"
            )
            RoamDataHandler.initializeSharedBlocking()
            migrateOffSwiftData()
            return true
        }

        func handleTypingNotification() {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: UserDefaultKeys.lastSupportTypingTime)
        }

        func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            Log.notifications.error("Failed to register for remote notifications with Error \(error, privacy: .public)")
        }
    }
#endif
