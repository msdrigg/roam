import SwiftUI

struct SettingsNavigationWrapper<Content>: View where Content: View {
    @Binding var path: [NavigationDestination]
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: NavigationDestination.self) { globalDestination in
                    switch globalDestination {
                    case let .settingsDestination(destination):
                        SettingsView(path: $path, destination: destination)
                    case .aboutDestination:
                        settingsSubview {
                            AboutView()
                        }
                    case let .deviceSettingsDestination(deviceId):
                        DeviceDetailView(deviceId: deviceId) {
                            popDestination()
                        }
                    case .keyboardShortcutDestinaion:
                        #if !os(watchOS)
                            settingsSubview {
                                KeyboardShortcutPanel()
                            }
                        #endif
                    case .messageDestination:
                        settingsSubview {
                            MessageView()
                        }
                    }
                }
        }
        .customAccentColorTint()
    }

    private func popDestination() {
        if path.count > 0 {
            path.removeLast()
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private func settingsSubview<Subview: View>(@ViewBuilder content: () -> Subview) -> some View {
#if os(macOS)
        content()
            .presentedWindowToolbarStyle(.unifiedCompact(showsTitle: false))
#else
        content()
#endif
    }

    @ViewBuilder
    private var backButton: some View {
#if os(macOS)
        Button(action: popDestination) {
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.iconOnly)
                .buttonStyle(.accessoryBar)
        }
        .help("Back")
#endif
    }
}
