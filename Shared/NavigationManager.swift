import Foundation
import SwiftUI

public enum WindowDestination: Equatable {
    case settings
    case keyboardShortcuts
    case messages
    case remote
}

@MainActor @Observable
final class NavigationManager {
    var navigationPath: [NavigationDestination] = []
    var messagingWindowOpenTrigger: UUID?
    var focusedWindow: WindowDestination?

    var last: NavigationDestination? {
        navigationPath.last
    }

    func append(_ destination: NavigationDestination) {
        navigationPath.append(destination)
    }
}
