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
    private var showingError: Error?
    private var showingErrorMessage: String?

    var last: NavigationDestination? {
        navigationPath.last
    }

    var displayedErrorMessage: String? {
        // TODO: THIS
        return nil
    }

    var displayedRecoverysuggestion: String? {
        // TODO: THIS
        return nil
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

    func showError(_ message: String, error: Error) {
        self.showingErrorMessage = message
        self.showingError = error
    }

    func clearError() {
        self.showingError = nil
        self.showingErrorMessage = nil
    }
}
