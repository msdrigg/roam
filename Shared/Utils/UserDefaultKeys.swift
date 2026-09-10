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
    static let customAccentColor: String = "customAccentColor"
    static let networkPermissionBannerDismissed = "networkPermissionBannerDismissed"
    static let networkExpensiveBannerDismissed = "networkExpensiveBannerDismissed"
    static let localNetworkPermissionGranted = "localNetworkPermissionGranted"
    static let macosKeysWindowHorizontal = "macosKeysWindowHorizontal"
    static let disablePastedUrlSuggestions = "disablePastedUrlSuggestions"
    static let deviceSortOrder = "deviceSortOrder"

    // Tips
    static let headphonesModeUsed = "headphonesModeUsed"
    static let audioInteractionCount = "audioInteractionCount"
    static let volumeOverHDMIHintShown = "volumeOverHDMIHintShown"

    // Tip jar / cosmetic unlocks
    static let cosmeticsGrandfathered = "cosmeticsGrandfathered"
    static let didEvaluateCosmeticsGrandfathering = "didEvaluateCosmeticsGrandfathering"
    static let developerCosmeticsUnlock = "developerCosmeticsUnlock"
    static let dateOfLastEntitlementRefresh = "dateOfLastEntitlementRefresh"
    static let alternateAppIcon = "alternateAppIcon"

    // Messaging
    static let lastTypingTime = "lastTypingTime"
    static let lastSupportTypingTime = "lastSupportTypingTime"
    static let lastApnsRequestTime = "lastApnsRequestTime"
    static let hasSentFirstMessage = "hasSentFirstMessage"

    // Records
    static let firstInstallVersion: String = "firstInstallVersion"
    static let alreadyResetHideShortcut: String = "alreadyResetHideShortcut"
    static let didMigrateOffSwiftData: String = "didMigrateOffSwiftData"
    static let didMigrateFileDataToGRDB: String = "didMigrateFileDataToGRDB"
}
