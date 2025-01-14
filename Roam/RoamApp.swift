import OSLog
import SwiftData
import SwiftUI
import TipKit
import UniformTypeIdentifiers
#if os(macOS)
    import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Main")

@main
struct RoamApp: App {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @Environment(\.openURL) private var openURL
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
        logger.info("Starting Roam")
        sharedModelContainer = getSharedModelContainer()

        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: tipsAppGroup))
        ])
    }

    var windowResizability: WindowResizability {
        if inScreenshotTestingContext() {
            return .contentSize
        } else {
#if os(visionOS)
            return .contentMinSize
#else
            return .automatic
#endif
        }
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
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        logger.info("Shutting down from willTerminate")
                    }
                    .frame(width: inScreenshotTestingContext() ? macOSWidth : nil, height: inScreenshotTestingContext() ? macOSHeigth : nil)
            }
            .enableBackgroundDragging()
            .defaultSize(width: macOSWidth, height: macOSHeigth)
            .windowResizability(windowResizability)
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

                if !appDelegate.navigationPath.showingSettingsView {
                    CommandGroup(replacing: CommandGroupPlacement.pasteboard) {
                        PasteButton(payloadType: String.self, onPaste: { item in
                            Task {
                                guard let first = item.first else {
                                    logger.info("Failed to paste because no item in pasteboard")
                                    return
                                }
                                guard let texteditId = appDelegate.ecpSessionState.textEditStatus.texteditId else {
                                    logger.info("Failed to paste because no textedit id")

                                    if let (app, params) = parsePastedUrl(first) {
                                        do {
                                            try await appDelegate.ecpSessionState.ecpSession?.openApp(app, params: params)
                                        } catch {
                                            logger.error("Error opening app from url app=\(app, privacy: .public) params=\(params, privacy: .public): \(error, privacy: .public)")
                                        }
                                    }

                                    return
                                }

                                do {
                                    try await appDelegate.ecpSessionState.ecpSession?.setTextEditText(first, for: texteditId)
                                } catch {
                                    logger.error("Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        })
                        .customKeyboardShortcut(.paste)

                        Button("Cut", systemImage: "clipboard", action: {
                            Task {
                                guard let texteditId = appDelegate.ecpSessionState.textEditStatus.texteditId else {
                                    logger.info("Failed to paste because no textedit id")
                                    return
                                }

                                if let texteditText = appDelegate.ecpSessionState.textEditStatus.text {
                                    logger.info("Cutting text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(texteditText, forType: .string)
                                }

                                do {
                                    try await appDelegate.ecpSessionState.ecpSession?.setTextEditText("", for: texteditId)
                                } catch {
                                    logger.error("Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        })
                        .customKeyboardShortcut(.cut)
                        .disabled(appDelegate.ecpSessionState.textEditStatus.texteditId == nil)

                        Button("Copy", systemImage: "clipboard", action: {
                            Task {
                                if let texteditText = appDelegate.ecpSessionState.textEditStatus.text {
                                    logger.info("Copying text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(texteditText, forType: .string)
                                }
                            }
                        })
                        .customKeyboardShortcut(.copy)
                        .disabled(appDelegate.ecpSessionState.textEditStatus.texteditId == nil)
                    }
                }

                if appDelegate.navigationPath.showingMessagesView {
                    CommandGroup(after: .appSettings) {
                        Divider()
                        Button("Refresh Chat Messages", systemImage: "arrow.clockwise.circle") {
                            appDelegate.refreshMessages()
                        }
                    }
                }

                CommandGroup(replacing: .help) {
                    Button("Roam Help", systemImage: "info.circle") {
                        openURL(URL(string: "https://roam.msd3.io/")!)
                    }

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

            MenuBarExtra("Roam Menu Bar", systemImage: "appletvremote.gen3", isInserted: self.$showMenuBar) {
                RemoteViewContained(isInMenuBar: true)
                    .modelContainer(sharedModelContainer)
                    .environment(\.uuidUpdater, uuidUpdater)
                    .environmentObject(appDelegate)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        logger.info("Shutting down from willTerminate")
                    }
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
                        .frame(width: inScreenshotTestingContext() ? macOSWidth : nil, height: inScreenshotTestingContext() ? macOSHeigth : nil)
                        .frame(minWidth: 400, minHeight: 950)
#endif
                        .environment(\.uuidUpdater, uuidUpdater)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                            logger.info("Shutting down from willTerminate")
                        }
            }
            #if os(visionOS)
            .windowResizability(windowResizability)
            .defaultSize(width: visionOSWidth, height: 1000)
            #endif
            .modelContainer(sharedModelContainer)
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
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .defaultSize(width: 500, height: 600)
            .windowResizability(.contentSize)
        #endif
    }

    var visionOSWidth: CGFloat {
        if CommandLine.arguments.contains("-WindowStyleVertical") {
            return 400
        } else {
            return 1500
        }
    }

    var macOSWidth: CGFloat {
        if CommandLine.arguments.contains("-WindowStyleVertical") {
            return 400
        } else {
            return 1200
        }
    }

    var macOSHeigth: CGFloat {
        if CommandLine.arguments.contains("-WindowStyleVertical") {
            return 1000
        } else {
            return 800
        }
    }
}
