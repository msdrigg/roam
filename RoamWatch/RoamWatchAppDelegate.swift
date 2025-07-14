import WatchKit
import UserNotifications
import Combine

@MainActor
final class RoamWatchAppDelegate: NSObject, ObservableObject, Sendable {
    @Published var navigationPath: NavigationManager
    @Published var networkMonitor: NetworkMonitor

    override init() {
        self.navigationPath = NavigationManager()
        self.networkMonitor = NetworkMonitor()
        super.init()
    }

    func handleTypingNotification() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: UserDefaultKeys.lastSupportTypingTime)
    }

    func refreshMessages(fetchCompletionHandler completionHandler: ((WKBackgroundFetchResult) -> Void)? = nil) {
        Task {
            let dataHandler = MessageDataHandler.shared
            let refreshResult = await dataHandler.refreshMessagesIfExpectingNewMessages()
            if refreshResult > 0 {
                completionHandler?(.newData)
            } else {
                completionHandler?(.noData)
            }

        }
    }
}

extension RoamWatchAppDelegate: WKApplicationDelegate {
    func didReceiveRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (WKBackgroundFetchResult) -> Void
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

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        Log.notifications.notice("didRegisterForRemoteNNotification")
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

    func applicationDidFinishLaunching() {
        Log.lifecycle.notice("Did finish launching")
        self.networkMonitor.startMonitoring()

        UNUserNotificationCenter.current().delegate = self

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
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: any Error) {
        Log.notifications.error("Failed to register for remote notifications with Error \(error, privacy: .public)")
    }
}

extension RoamWatchAppDelegate: UNUserNotificationCenterDelegate {
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
}
