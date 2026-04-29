import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsNavigationWrapper<Content>: View where Content: View {
    @Binding var path: [NavigationDestination]
    let showsMacSettingsControls: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(
        path: Binding<[NavigationDestination]>,
        showsMacSettingsControls: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._path = path
        self.showsMacSettingsControls = showsMacSettingsControls
        self.content = content
    }

    var body: some View {
#if os(macOS)
        if showsMacSettingsControls {
            navigationStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .removeMacSettingsTopInset()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    settingsNavigationBar
                }
                .hideMacSettingsWindowToolbar()
                .customAccentColorTint()
        } else {
            navigationStack
                .customAccentColorTint()
        }
#else
        navigationStack
            .customAccentColorTint()
#endif
    }

    private var navigationStack: some View {
        NavigationStack(path: $path) {
            settingsContent {
                content()
            }
                .navigationDestination(for: NavigationDestination.self) { globalDestination in
                    switch globalDestination {
                    case let .settingsDestination(destination):
                        settingsContent {
                            SettingsView(path: $path, destination: destination)
                        }
                    case .aboutDestination:
                        settingsSubview {
                            AboutView()
                        }
                    case let .deviceSettingsDestination(deviceId):
                        settingsContent {
                            DeviceDetailView(deviceId: deviceId) {
                                popDestination()
                            }
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
    }

    private func popDestination() {
        if path.count > 0 {
            path.removeLast()
        } else {
            dismiss()
        }
    }

#if os(macOS)
    private func closeSettings() {
        let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first {
            $0.identifier == NSUserInterfaceItemIdentifier(rawValue: "com_apple_SwiftUI_Settings_window")
        }
        let replacementWindow = windowToActivateAfterClosingSettings(settingsWindow: settingsWindow)

        if let replacementWindow {
            NSApp.activate(ignoringOtherApps: true)
            replacementWindow.makeKeyAndOrderFront(nil)
            replacementWindow.orderFrontRegardless()
        }

        settingsWindow?.performClose(nil)
    }

    private func windowToActivateAfterClosingSettings(settingsWindow: NSWindow?) -> NSWindow? {
        let settingsIdentifier = NSUserInterfaceItemIdentifier(rawValue: "com_apple_SwiftUI_Settings_window")
        let mainIdentifier = NSUserInterfaceItemIdentifier(rawValue: "main")

        func isReplacementCandidate(_ window: NSWindow) -> Bool {
            window !== settingsWindow
                && window.identifier != settingsIdentifier
                && window.isVisible
                && !window.isMiniaturized
                && window.canBecomeKey
        }

        return NSApp.windows.first {
            $0.identifier == mainIdentifier && isReplacementCandidate($0)
        } ?? NSApp.windows.first(where: isReplacementCandidate)
    }
#endif

    @ViewBuilder
    private func settingsContent<Subview: View>(@ViewBuilder content: () -> Subview) -> some View {
#if os(macOS)
        if showsMacSettingsControls {
            content()
                .removeMacSettingsTopInset()
        } else {
            content()
        }
#else
        content()
#endif
    }

    @ViewBuilder
    private func settingsSubview<Subview: View>(@ViewBuilder content: () -> Subview) -> some View {
        settingsContent {
            content()
        }
    }

    @ViewBuilder
    private var settingsNavigationBar: some View {
#if os(macOS)
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Spacer()

                if !path.isEmpty {
                    Button("Back", action: popDestination)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                }

                Button("Done", action: closeSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
#endif
    }
}

private extension View {
    @ViewBuilder
    func removeMacSettingsTopInset() -> some View {
#if os(macOS)
        self
            .ignoresSafeArea(.container, edges: .top)
            .contentMargins(.top, 0, for: .scrollContent)
#else
        self
#endif
    }

    @ViewBuilder
    func hideMacSettingsWindowToolbar() -> some View {
#if os(macOS)
        if #available(macOS 15.0, *) {
            self.toolbarVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
#else
        self
#endif
    }
}
