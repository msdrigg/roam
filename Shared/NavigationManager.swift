import Foundation
import SwiftUI

#if os(macOS)
public enum WindowDestination: Equatable {
    case settings
    case keyboardShortcuts
    case messages
    case remote
}
#endif

#if !os(macOS) && !os(watchOS)
enum AppTab: Hashable {
    case device(String)
}
#endif

@MainActor @Observable
final class NavigationManager {
    /// On macOS / watchOS, this is the global app navigation stack.
    var navigationPath: [NavigationDestination] = []

    #if !os(macOS) && !os(watchOS)
    var selectedTab: AppTab = .device("")
    var settingsNavigationPath: [NavigationDestination] = []
    var showSettings: Bool = false
    #endif

    #if os(macOS)
    var focusedWindow: WindowDestination?
    var messagingWindowOpenTrigger: UUID?
    #endif

    var showAddDevice: Bool = false

    var last: NavigationDestination? {
        #if !os(macOS) && !os(watchOS)
        settingsNavigationPath.last
        #else
        navigationPath.last
        #endif
    }

    /// Push onto the active navigation stack. On iOS / visionOS this presents
    /// the settings sheet, whose stack is separate from the selected device tab.
    /// `.settingsDestination(.global)` is treated as "go to settings root."
    func append(_ destination: NavigationDestination) {
        #if !os(macOS) && !os(watchOS)
        showSettings = true
        if case .settingsDestination(.global) = destination {
            settingsNavigationPath.removeAll()
            return
        }
        settingsNavigationPath.append(destination)
        #else
        navigationPath.append(destination)
        #endif
    }

    func openMessages() {
        if last != .messageDestination {
            append(.messageDestination)
        } else {
            #if !os(macOS) && !os(watchOS)
            showSettings = true
            #endif
        }
    }

    func openKeyboardShortcuts() {
        if last != .keyboardShortcutDestinaion {
            append(.keyboardShortcutDestinaion)
        } else {
            #if !os(macOS) && !os(watchOS)
            showSettings = true
            #endif
        }
    }

    func openAbout() {
        if last != .aboutDestination {
            append(.aboutDestination)
        } else {
            #if !os(macOS) && !os(watchOS)
            showSettings = true
            #endif
        }
    }

    func openDeviceSettings(_ id: String) {
        append(.deviceSettingsDestination(id))
    }

    #if os(macOS)
    func showingAddDevice(for focusedWindow: WindowDestination) -> Binding<Bool> {
        if focusedWindow == self.focusedWindow {
            return Binding(get: { self.showAddDevice }, set: { self.showAddDevice = $0 })
        } else {
            return Binding(get: { false }, set: { _ in })
        }
    }
    #endif
}
