import OSLog
import SwiftData
import SwiftUI
import TipKit
import UniformTypeIdentifiers
#if os(macOS)
    import AppKit
#endif

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
    @KeyboardShortcutStorage(.showRoam) var showRoamShortcut: CustomKeyboardShortcut?
    @KeyboardShortcutStorage(.keyboardShortcuts) var keyboardShortcutPanelShortcut: CustomKeyboardShortcut?
    @KeyboardShortcutStorage(.chatWithDeveloper) var messagesShortcut: CustomKeyboardShortcut?
    @State var hotkeyRef: Any?

    var uuidUpdater: UUIDUpdater {
        appDelegate.uuidUpdater
    }

    var sharedModelContainer: ModelContainer
    init() {
        Log.lifecycle.notice("Starting Roam")
        #if !os(macOS)
        installAborter()
        #endif
        installSIGPIPEHandler()

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
                        NSApp.forceFront("main")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        Log.lifecycle.notice("Shutting down main body from willTerminate")
                    }
                    .frame(width: inScreenshotTestingContext() ? macOSWidth : nil, height: inScreenshotTestingContext() ? macOSHeigth : nil)
                    .colorScheme(.dark)
            }
            .keyboardShortcut(showRoamShortcut?.shortcut)
            .onChange(of: showRoamShortcut, initial: true) { _, new in
                if let currentHotkeyRef = hotkeyRef {
                    hotkeyRef = nil
                    Log.lifecycle.notice("Uninstalling old global hotkey \(String(describing: showRoamShortcut), privacy: .public)")
                    do {
                        try uninstallCarbonHandler(currentHotkeyRef)
                    } catch {
                        Log.lifecycle.warning("Unable to uninstall global hotkey with error \(error, privacy: .public)")
                    }
                } else {
                    Log.lifecycle.notice("No global hotkey to uninstall")
                }
                do {
                    if let shortcut = new, let key = shortcut.key {
                        Log.lifecycle.notice("Installing global hotkey \(String(describing: shortcut), privacy: .public)")
                        hotkeyRef = try installCarbonHandler(key: key, modifiers: shortcut.modifiers)
                    } else {
                        Log.lifecycle.notice("No global hotkey to install")
                    }
                } catch {
                    Log.lifecycle.warning("Unable to install global hotkey with error \(error, privacy: .public)")
                }
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
                            NSApp.forceFront("about")
                        }
                    }, label: {
                        Text("About Roam", comment: "Button to open the about page of the Roam app")
                    })
                }

                if appDelegate.navigationPath.focusedWindow == .remote {
                    CommandGroup(replacing: CommandGroupPlacement.pasteboard) {
                        PasteButton(payloadType: String.self, onPaste: { item in
                            Task {
                                guard let first = item.first else {
                                    Log.lifecycle.notice("Failed to paste because no item in pasteboard")
                                    return
                                }
                                guard let texteditId = appDelegate.ecpMonitor.textEditStatus.texteditId else {
                                    Log.lifecycle.notice("Failed to paste because no textedit id")

                                    if let (app, params) = parsePastedUrl(first) {
                                        do {
                                            try await appDelegate.ecpMonitor.ecpClient?.launchApp(app, params: params)
                                        } catch {
                                            Log.lifecycle.error("Error opening app from url app=\(app, privacy: .public) params=\(params, privacy: .public): \(error, privacy: .public)")
                                        }
                                    }

                                    return
                                }

                                do {
                                    try await appDelegate.ecpMonitor.ecpClient?.setTextEdit(first, texteditId: texteditId)
                                } catch {
                                    Log.lifecycle.error("Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        })
                        .customKeyboardShortcut(.paste)

                        Button("Cut", systemImage: "clipboard", action: {
                            Task {
                                guard let texteditId = appDelegate.ecpMonitor.textEditStatus.texteditId else {
                                    Log.lifecycle.notice("Failed to paste because no textedit id")
                                    return
                                }

                                if let texteditText = appDelegate.ecpMonitor.textEditStatus.text {
                                    Log.lifecycle.notice("Cutting text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(texteditText, forType: .string)
                                }

                                do {
                                    try await appDelegate.ecpMonitor.ecpClient?.setTextEdit("", texteditId: texteditId)
                                } catch {
                                    Log.lifecycle.error("Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        })
                        .customKeyboardShortcut(.cut)
                        .disabled(appDelegate.ecpMonitor.textEditStatus.texteditId == nil)

                        Button("Copy", systemImage: "clipboard", action: {
                            Task {
                                if let texteditText = appDelegate.ecpMonitor.textEditStatus.text {
                                    Log.lifecycle.notice("Copying text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(texteditText, forType: .string)
                                }
                            }
                        })
                        .customKeyboardShortcut(.copy)
                        .disabled(appDelegate.ecpMonitor.textEditStatus.texteditId == nil)
                    }
                }

                if appDelegate.navigationPath.focusedWindow == .messages{
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

                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApp.forceFront("messages")
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
                        Log.lifecycle.notice("Shutting meuBar down from willTerminate")
                    }
                    .colorScheme(.dark)
            }
            .menuBarExtraStyle(.window)
        #else
            WindowGroup {
                    RemoteView()
#if os(visionOS)
                        .frame(width: inScreenshotTestingContext() ? macOSWidth : nil, height: inScreenshotTestingContext() ? macOSHeigth : nil)
                        .frame(minWidth: 400, minHeight: 950)
#endif
                        .environment(\.uuidUpdater, uuidUpdater)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                            Log.lifecycle.notice("Shutting down from willTerminate")
                        }
                        .colorScheme(.dark)
            }
            #if os(visionOS)
            .windowResizability(windowResizability)
            .defaultSize(width: visionOSWidth, height: 1000)
            #endif
            .modelContainer(sharedModelContainer)
        #endif

        #if os(macOS)
            Window(String(localized: "Messages", comment: "Window header for the messages window"), id: "messages") {
                MessageView()
                    .frame(width: 400)
                    .translucentBackground()
                    .environment(\.uuidUpdater, uuidUpdater)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("messages")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .colorScheme(.dark)
            }
            .keyboardShortcut(messagesShortcut?.shortcut)
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)

            Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
                    .translucentBackground()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("keyboard-shortcuts")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({!$0.isExcludedFromWindowsMenu && $0.canBecomeKey && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .colorScheme(.dark)
            }
            .keyboardShortcut(keyboardShortcutPanelShortcut?.shortcut)
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
                    }
                    .onDisappear {
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .colorScheme(.dark)
            }
            .modelContainer(sharedModelContainer)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .defaultSize(width: 500, height: 600)
            .windowResizability(.contentSize)

            Window("About Roam", id: "about") {
                ExternalAboutView()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .translucentBackground()
                    .disableWindowMinimize()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("about")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({$0.level != .statusBar && $0.isVisible}).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .colorScheme(.dark)
            }
            .disableRestoration()
            .defaultSize(width: 450, height: 200)
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
