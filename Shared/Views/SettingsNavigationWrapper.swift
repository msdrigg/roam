import SwiftUI

struct SettingsNavigationWrapper<Content>: View where Content: View {
    @Binding var path: [NavigationDestination]
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.uuidUpdater) private var updater

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: NavigationDestination.self) { globalDestination in
                    switch globalDestination {
                    case let .settingsDestination(destination):
                        SettingsView(path: $path, destination: destination)
                    case .aboutDestination:
                        AboutView()
                    case let .deviceSettingsDestination(deviceId):
                        DeviceDetailView(deviceId: deviceId) {
                            if path.count > 0 {
                                path.removeLast()
                            }
                            updater?.update()
                        }
                    case .keyboardShortcutDestinaion:
                        #if !os(watchOS)
                            KeyboardShortcutPanel()
                        #endif
                    case .messageDestination:
                            MessageView()
                    }
                }
        }
        .customAccentColorTint()
    }
}
