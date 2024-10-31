import OSLog
import SwiftData
import SwiftUI
import TipKit
#if os(macOS)
    import AppKit
#endif

@main
struct RoamApp: App {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    #if os(macOS)
        @NSApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #elseif !os(watchOS)
        @UIApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #endif

    @AppStorage(UserDefaultKeys.showMenuBar) private var showMenuBar: Bool = false

    @ObservedObject var uuidUpdater = UUIDUpdater()

    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: tipsAppGroup))
        ])
    }

    var body: some Scene {
        #if os(macOS)
            Window("Roam", id: "main") {
                RemoteView()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .environment(\.uuidUpdater, uuidUpdater)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            .enableBackgroundDragging()
            .defaultSize(width: 400, height: 1000)
            .trailingPosition()
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                    Button(action: {
                        openWindow(id: "about")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }, label: {
                        Text("About Roam", comment: "Button to open the about page of the Roam app")
                    })
                }
                CommandGroup(after: .help) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)

                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }

                CommandGroup(after: .singleWindowList) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)
                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())

            MenuBarExtra("Roam Menu Bar", systemImage: "appletvremote.gen3", isInserted: self.$showMenuBar) {
                RemoteViewContained(isInMenuBar: true)
                    .modelContainer(sharedModelContainer)
                    .environment(\.createDataHandler, dataHandlerCreator())
                    .environment(\.uuidUpdater, uuidUpdater)
            }
            .menuBarExtraStyle(.window)

            Window("About Roam", id: "about") {
                ExternalAboutView()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .translucentBackground()
                    .disableWindowMinimize()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            .disableRestoration()
            .defaultSize(width: 450, height: 200)
        #else
            WindowGroup {
                    RemoteView()
#if os(visionOS)
                        .frame(minWidth: 400, minHeight: 950)
#endif
                        .environment(\.uuidUpdater, uuidUpdater)
            }
            #if os(visionOS)
            .windowResizability(.contentMinSize)
            .defaultSize(width: 400, height: 1000)
            #endif
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
        #endif

        #if os(macOS)
            Window(String(localized: "Roam Messages", comment: "Window header for the messages window"), id: "messages") {
                MessageView()
                    .frame(width: 400)
                    .translucentBackground()
                    .environment(\.uuidUpdater, uuidUpdater)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())

            Window("Roam Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
                    .translucentBackground()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        if NSApp.windows.filter({!$0.isExcludedFromWindowsMenu && $0.canBecomeKey && $0.isVisible}).count <= 1 {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
        #endif

        #if os(macOS)
            Settings {
                MacSettings()
                    .translucentBackground()
                    .enableResize()
                    .environment(\.uuidUpdater, uuidUpdater)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app

                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .defaultSize(width: 500, height: 600)
            .windowResizability(.contentSize)
        #endif
    }
}
