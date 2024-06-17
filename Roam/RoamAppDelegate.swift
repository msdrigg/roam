import Foundation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "AppDelegate"
)

// Optional: Send the device token to your server
func sendDeviceTokenToServer(_ token: String) async {
    do {
        try await sendMessage(message: nil, apnsToken: token)
    } catch {
        logger.error("Error sending apns token to server \(error)")
    }
}

#if os(macOS)
    import AppKit

    class RoamAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
        @Published var navigationPath: NavigationManager
        @Published var messagingWindowOpenTrigger: UUID?

        @MainActor
        override init() {
            navigationPath = NavigationManager()
            super.init()
            UNUserNotificationCenter.current().delegate = self
            logger.info("Setting Notifications delegate to self")
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            let hasSentFirstMessage = UserDefaults.standard.bool(forKey: "hasSentFirstMessage")
            if hasSentFirstMessage {
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "lastApnsRequestTime")
                requestNotificationPermission()
            }

        }

        func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            let tokenParts = deviceToken.map { data -> String in
                String(format: "%02.2hhx", data)
            }
            let token = tokenParts.joined()
            logger.info("Device Token: \(token)")

            Task {
                await sendDeviceTokenToServer(token)
                UserDefaults.standard.set(true, forKey: "hasSentFirstMessage")
            }
        }

        func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
            logger.info("Received remote notification")
            refreshMessages()
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            logger.info("didReceive notification. Showing Messages...")
            refreshMessages()
            messagingWindowOpenTrigger = UUID()
            completionHandler()
        }

        func refreshMessages() {
            Task {
                let dataHandler = DataHandler(modelContainer: getSharedModelContainer())
                await dataHandler.refreshMessagesIfExpectingNewMessages()
            }
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            logger.info("WillPresent notification. Refreshing messages...")
            refreshMessages()
            completionHandler(.badge)
        }

        func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            logger.error("Failed to register with Error \(error)")
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

    class RoamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject, Sendable {
        @Published var navigationPath: NavigationManager = NavigationManager()

        private var cancellables: Set<AnyCancellable> = []

        override init() {
            super.init()
            UNUserNotificationCenter.current().delegate = self
        }

        func application(
            _ application: UIApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) {
            logger.info("Received remote notifications")
            requestMessages(fetchCompletionHandler: completionHandler)
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            let tokenParts = deviceToken.map { data -> String in
                String(format: "%02.2hhx", data)
            }
            let token = tokenParts.joined()
            logger.info("Device Token: \(token)")

            Task {
                await sendDeviceTokenToServer(token)
                UserDefaults.standard.set(true, forKey: "hasSentFirstMessage")
            }
        }

        #if !os(tvOS)
        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            logger.info("didReceive notification. Showing Messages...")
            DispatchQueue.main.async {
                if self.navigationPath.last != NavigationDestination.messageDestination {
                    self.navigationPath.append(NavigationDestination.messageDestination)
                }
            }

            completionHandler()
        }
        #endif

        func requestMessages(fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)? = nil) {
            Task {
                let dataHandler = DataHandler(modelContainer: getSharedModelContainer())
                let refreshResult = await dataHandler.refreshMessagesIfExpectingNewMessages()
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
            logger.info("willPresent notification. Refreshing...")
            DispatchQueue.main.async {
                self.requestMessages()
            }
            completionHandler(.badge)
        }

        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            let hasSentFirstMessage = UserDefaults.standard.bool(forKey: "hasSentFirstMessage")
            if hasSentFirstMessage {
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "lastApnsRequestTime")
                requestNotificationPermission()
            }

            return true

        }

        func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
            logger.error("Failed to register for remote notifications with Error \(error)")
        }
    }
#endif
