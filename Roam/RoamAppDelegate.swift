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
    func forceFront(_ id: String) {
        let mainWindow: NSWindow? = self.windows.first {
            $0.identifier == NSUserInterfaceItemIdentifier(rawValue: id)
        }

        Log.lifecycle.notice("Making window front \(id, privacy: .public), \(mainWindow?.title ?? "nil", privacy: .public)")
        NSApplication.shared.activate(ignoringOtherApps: true)

        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
    }
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

        override init() {
            self.navigationPath = NavigationManager()
            self.ecpMonitor = ECPMonitor()
            self.networkMonitor = NetworkMonitor()
            super.init()
            UNUserNotificationCenter.current().delegate = self
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
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            Log.notifications.notice("didReceive notification. Showing Messages...")
            DispatchQueue.main.async {
                self.refreshMessages()
                if self.navigationPath.last != NavigationDestination.messageDestination {
                    self.navigationPath.append(NavigationDestination.messageDestination)
                }
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
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            Log.notifications.notice("willPresent notification. Refreshing...")
            DispatchQueue.main.async {
                self.refreshMessages()
            }
            completionHandler(.badge)
        }

        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            self.networkMonitor.startMonitoring()
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
