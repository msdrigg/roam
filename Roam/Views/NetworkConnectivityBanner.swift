import SwiftUI

struct NetworkConnectivityBanner: View {
#if os(watchOS)
    @EnvironmentObject private var appDelegate: RoamWatchAppDelegate
#else
    @EnvironmentObject private var appDelegate: RoamAppDelegate
#endif
    @ObservedObject private var databaseStatus = DatabaseStatusMonitor.shared

    private var networkMonitor: NetworkMonitor {
        self.appDelegate.networkMonitor
    }

#if !os(watchOS)
    private var ecpSessionState: ECPMonitor {
        appDelegate.ecpMonitor
    }

    private var ecpSession: ECPWebsocketClient? {
        appDelegate.ecpMonitor.ecpClient
    }
#endif

    @AppStorage(UserDefaultKeys.networkPermissionBannerDismissed) private var networkPermissionBannerDismissed: Bool = false
    @AppStorage(UserDefaultKeys.networkExpensiveBannerDismissed) private var networkExpensiveBannerDismissed: Bool = false
    @AppStorage(UserDefaultKeys.localNetworkPermissionGranted) private var localNetworkPermissionGranted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            databaseBody
            mainBody
        }
            .onAppear {
                networkPermissionBannerDismissed = false
            }
    }

    var connectedForSure: Bool {
        #if !os(watchOS)
        self.ecpSessionState.status == .connected
        #else
        false
        #endif
    }

    @ViewBuilder
    var databaseBody: some View {
        if let issue = databaseStatus.issue {
            NotificationBanner(
                message: issue.message,
                onClick: issue.isRetryable && issue.isVolatile ? {
                    Task {
                        await RoamDataHandler.shared.retryOpeningPersistentDatabase()
                    }
                } : nil,
                level: issue.kind == .corrupt ? .error : .warning
            )
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    var mainBody: some View {
        if !connectedForSure {
            if networkMonitor.networkConnection == .none {
                NotificationBanner(message: String(
                    localized: "No network connection",
                    comment: "Warning indicator message that there is no network connection")
                )
                .padding(.bottom, 8)
            } else if networkMonitor.networkConnection == .remote || networkMonitor.networkConnection == .other {
                NotificationBanner(message: String(
                    localized: "No WiFi connection detected",
                    comment: "Warning indicator message that there is no WiFi network connection"
                ), level: .warning)
                .padding(.bottom, 8)
            } else if networkMonitor.networkConnection == .expensiveLocal && !self.networkExpensiveBannerDismissed {
                NotificationBanner(message: String(
                    localized: "No valid WiFi connection detected. You may be connected to a hotspot instead of your home WiFi network",
                    comment: "Warning indicator message that there is no WiFi network connection"
                ), onDismiss: {
                    self.networkExpensiveBannerDismissed = true
                }, level: .warning)
                .padding(.bottom, 8)
            } else if self.localNetworkPermissionGranted == false && !self.networkPermissionBannerDismissed {
#if os(macOS)
                NotificationBanner(message: String(
                    localized: "Local network permission may not be granted. Please open System Settings and navigate to Privacy and Security -> Local Network and enable access for Roam",
                    comment: "Warning indicator message that there is no local network permission"
                ), onDismiss: {
                    self.networkPermissionBannerDismissed = true
                })
                .padding(.bottom, 8)
#elseif !os(watchOS)
                NotificationBanner(message: String(
                    localized:
                        "Local network permission may not be granted. Please navigate to System Settings -> Apps -> Roam and enable Local Network",
                    comment: "Warning indicator message that there is no local network permission"
                ), onDismiss: {
                    self.networkPermissionBannerDismissed = true
                })
                .padding(.bottom, 8)
#endif
            }
        }
    }
}
