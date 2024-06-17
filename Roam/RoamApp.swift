import OSLog
import SwiftData
import SwiftUI
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

    @ObservedObject var uuidUpdater = UUIDUpdater()

    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }

    var body: some Scene {
        #if os(macOS)
            Window("Roam", id: "main") {
                RemoteView()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .environment(\.uuidUpdater, uuidUpdater)
            }
            .enableBackgroundDragging()
            .defaultSize(width: 400, height: 1000)
            .trailingPosition()
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                    Button(action: {
                        openWindow(id: "about")
                    }, label: {
                        Text("About Roam", comment: "Button to open the about page of the Roam app")
                    })
                }
                CommandGroup(after: .help) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)

                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }

                CommandGroup(after: .singleWindowList) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)
                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())

            Window("About Roam", id: "about") {
                ExternalAboutView()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .translucentBackground()
                    .disableWindowMinimize()
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
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())

            Window("Roam Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
                    .translucentBackground()
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
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .defaultSize(width: 500, height: 600)
            .windowResizability(.contentSize)
        #endif
    }
}
