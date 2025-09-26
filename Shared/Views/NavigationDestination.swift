import SwiftUI

enum NavigationDestination: Hashable {
    case settingsDestination(SettingsDestination)
    case aboutDestination
    case deviceSettingsDestination(String)
    case keyboardShortcutDestinaion
    case messageDestination
}

enum SettingsDestination {
    case global
    case debugging
}
