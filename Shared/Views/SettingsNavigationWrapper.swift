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
                        #if !APPCLIP
                            SettingsView(path: $path, destination: destination)
                        #endif
                    case .aboutDestination:
                        #if !APPCLIP
                            AboutView()
                        #endif
                    case let .deviceSettingsDestination(deviceId):
                        #if !APPCLIP
                            DeviceDetailView(deviceId: deviceId) {
                                if path.count > 0 {
                                    path.removeLast()
                                }
                                print("Updating here!! \(updater != nil)")
                                updater?.update()
                            }
                        #endif
                    case .keyboardShortcutDestinaion:
                        #if !os(watchOS) && !os(tvOS)
                            KeyboardShortcutPanel()
                        #endif
                    case .messageDestination:
                        #if !os(watchOS)
                            MessageView()
                        #endif
                    }
                }
        }
    }
}
