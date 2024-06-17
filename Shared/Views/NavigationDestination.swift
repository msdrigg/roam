import SwiftUI
import SwiftData

enum NavigationDestination: Hashable {
    case settingsDestination(SettingsDestination)
    case aboutDestination
    case deviceSettingsDestination(PersistentIdentifier)
    case keyboardShortcutDestinaion
    case messageDestination
}

enum SettingsDestination {
    case global
    case debugging
}
