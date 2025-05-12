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
    var showAddDevice: Bool = false

    var last: NavigationDestination? {
        navigationPath.last
    }

    func showingAddDevice(for focusedWindow: WindowDestination) -> Binding<Bool> {
        if focusedWindow == self.focusedWindow {
            return Binding(get: { self.showAddDevice }, set: { self.showAddDevice = $0 })
        } else {
            return Binding(get: { false }, set: { _ in })
        }
    }

    func append(_ destination: NavigationDestination) {
        navigationPath.append(destination)
    }
}
