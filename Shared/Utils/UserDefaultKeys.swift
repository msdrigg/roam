import Foundation

enum UserDefaultKeys {
    // Requesting review
    static let userMajorActionCount: String = "userMajorAction"
    static let appVersionAtLastReviewRequest: String = "appVersionAtLastReviewRequest"
    static let dateOfLastReviewRequest: String = "dateOfLastReviewRequest"

    // App settings
    static let shouldScanIPRangeAutomatically: String = "scanIPAutomatically"
    static let shouldDisableAllAutoScanning: String = "disableAllScanning"
    static let shouldControlVolumeWithHWButtons: String = "controlVolumeWithHWButtons"
    static let showMenuBar: String = "showMenuBar"
}
