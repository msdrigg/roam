import SwiftUI

struct WrongAttemptsKey: EnvironmentKey {
    static let defaultValue: WrongAttemptsTracker? = nil
}

extension EnvironmentValues {
    var wrongAttempts: WrongAttemptsTracker? {
        get { self[WrongAttemptsTracker.self] }
        set { self[WrongAttemptsTracker.self] = newValue }
    }
}

@MainActor @Observable
final class WrongAttemptsTracker {
    var attempts: Int = 0
}
