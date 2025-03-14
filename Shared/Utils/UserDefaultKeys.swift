import Foundation

enum UserDefaultKeys {
    // Requesting review
    static let userMajorActionCount: String = "userMajorAction"
    static let appVersionAtLastReviewRequest: String = "appVersionAtLastReviewRequest"
    static let dateOfLastReviewRequest: String = "dateOfLastReviewRequest"

    // App settings
    static let shouldScanIPRangeAutomatically: String = "scanIPAutomatically"
    static let shouldControlVolumeWithHWButtons: String = "controlVolumeWithHWButtons"
    static let showMenuBar: String = "showMenuBar"
    static let networkPermissionBannerDismissed = "networkPermissionBannerDismissed"
    static let networkExpensiveBannerDismissed = "networkExpensiveBannerDismissed"
    static let localNetworkPermissionGranted = "localNetworkPermissionGranted"

    // Messaging
    static let lastTypingTime = "lastTypingTime"
    static let lastSupportTypingTime = "lastSupportTypingTime"
    static let lastApnsRequestTime = "lastApnsRequestTime"
    static let hasSentFirstMessage = "hasSentFirstMessage"

    // Records
    static let firstInstallVersion: String = "firstInstallVersion"
    static let alreadyResetHideShortcut: String = "alreadyResetHideShortcut"
}
