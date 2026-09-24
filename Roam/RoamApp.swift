import OSLog
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
    @KeyboardShortcutStorage(.keyboardShortcuts) var keyboardShortcutPanelShortcut:
        CustomKeyboardShortcut?
    @KeyboardShortcutStorage(.chatWithDeveloper) var messagesShortcut: CustomKeyboardShortcut?
    @State var hotkeyRef: Any?
    #if os(macOS)
        @State private var minimumWindowWidth: CGFloat?
    #endif

    let metricManager = RoamMetricManager.shared
    init() {
        // Before anything else worth logging: this run's log file has to exist
        // for this run's lines to survive it, and the backtrace trap is only
        // useful if it beats the crash.
        FileLog.start()
        CrashStackTrap.install()
        Log.lifecycle.notice("Starting Roam")
        #if !os(macOS)
            installAborter()
        #endif
        installSIGPIPEHandler()

        // Nothing outside this process reads the tips store -- the widget has no
        // TipKit at all -- so it has no business in the group container, where a
        // suspended lock holder is what 0xdead10cc kills for. TipKit loads that
        // store on its own Task, well after `configure` returns, so no assertion
        // taken here could have covered it anyway.
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])

        // UIKit opens the shared database in willFinishLaunchingWithOptions,
        // after UIApplication exists and can grant a background task.
        #if os(macOS)
            RoamDataHandler.initializeSharedAtLaunch()
            migrateOffSwiftData()
        #endif
    }

    var windowResizability: WindowResizability {
        if inScreenshotTestingContext() {
            return .contentSize
        } else {
            #if os(macOS)
                return .contentSize
            #elseif os(visionOS)
                return .contentMinSize
            #else
                return .automatic
            #endif
        }
    }

    #if os(macOS)
        // `body` used to build both scenes, all five command groups and every
        // modifier in a single getter. Each application allocas a new, larger
        // value sized from runtime type metadata, and nothing is released until
        // the getter returns -- the cost accumulated across the whole scene
        // tree, on the same main-thread stack the 1.50/1.51 overflows ran out
        // of. Split into stages so each one's temporaries pop when it returns.
        private var mainWindowScene: some Scene {
            Window("Roam", id: "main") {
                RemoteView()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .onAppear {
                        NSApp.setActivationPolicyDeferred(.regular)
                        NSApp.forceFront("main")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicyDeferred(.accessory)
                        }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: NSApplication.willTerminateNotification)
                    ) { _ in
                        Log.lifecycle.notice("Shutting down main body from willTerminate")
                    }
                    .onPreferenceChange(MinimumWindowWidthKey.self) { width in
                        minimumWindowWidth = width
                    }
                    .frame(
                        minWidth: minimumWindowWidth ?? macOSMinWidth,
                        idealWidth: macOSWidth,
                        maxWidth: macOSMaxWidth,
                        minHeight: macOSMinHeight,
                        idealHeight: macOSHeigth,
                        maxHeight: macOSMaxHeight
                    )
                    .preferredColorScheme(.dark)
            }
            .onChange(of: showRoamShortcut, initial: true) { _, new in
                if let currentHotkeyRef = hotkeyRef {
                    hotkeyRef = nil
                    Log.lifecycle.notice(
                        "Uninstalling old global hotkey \(String(describing: showRoamShortcut), privacy: .public)"
                    )
                    do {
                        try uninstallCarbonHandler(currentHotkeyRef)
                    } catch {
                        Log.lifecycle.warning(
                            "Unable to uninstall global hotkey with error \(error, privacy: .public)"
                        )
                    }
                } else {
                    Log.lifecycle.notice("No global hotkey to uninstall")
                }
                do {
                    if let shortcut = new, let key = shortcut.key {
                        Log.lifecycle.notice(
                            "Installing global hotkey \(String(describing: shortcut), privacy: .public)"
                        )
                        hotkeyRef = try installCarbonHandler(
                            key: key, modifiers: shortcut.modifiers)
                    } else {
                        Log.lifecycle.notice("No global hotkey to install")
                    }
                } catch {
                    Log.lifecycle.warning(
                        "Unable to install global hotkey with error \(error, privacy: .public)")
                }
            }
            .enableBackgroundDragging()
            .defaultSize(width: macOSWidth, height: macOSHeigth)
            .windowResizability(windowResizability)
            .trailingPosition()
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands { roamCommands }
        }

        @CommandsBuilder
        private var roamCommands: some Commands {
            appInfoCommand
            pasteboardCommand
            addDeviceCommand
            refreshMessagesCommand
            windowCommands
            helpCommand
        }

        /// The Window menu entries, carrying the shortcuts that open each
        /// window.
        ///
        /// These shortcuts used to be `Scene.keyboardShortcut` on the `Window`
        /// scenes. Do not move them back. On macOS 26.5 through 26.7 that
        /// modifier is fatal at launch: after every scene update,
        /// `AppDelegate.scenesDidChange` copies the scene list's shortcut table
        /// into `AppGraph._sceneKeyboardShortcuts` with `AGGraphSetValue`,
        /// which compares a dictionary by storage identity rather than by
        /// contents, so a non-empty table reads as changed on every pass. That
        /// attribute feeds the root scene environment, so the "change" dirties
        /// every scene body, the scene list gets a new version, and
        /// `scenesDidChange` calls `AppGraph.graphDidChange` again from inside
        /// the pass that called it, until the main thread runs off its stack
        /// (roam 1.50 through 1.55, `EXC_BAD_ACCESS` in Stack Guard). An empty
        /// table is the shared empty dictionary storage and compares equal, so
        /// the pass settles after one round. Menu commands land in
        /// `CommandsList`, which is not part of that table.
        @CommandsBuilder
        private var windowCommands: some Commands {
            CommandGroup(replacing: .windowList) {
                Button(
                    action: { showWindow("main") },
                    label: {
                        Text("Roam", comment: "Window menu item that opens the main Roam window")
                    }
                )
                .keyboardShortcut(showRoamShortcut?.shortcut)

                Button(
                    action: { showWindow("messages") },
                    label: {
                        Text("Messages", comment: "Window menu item that opens the messages window")
                    }
                )
                .keyboardShortcut(messagesShortcut?.shortcut)

                Button(
                    action: { showWindow("keyboard-shortcuts") },
                    label: {
                        Text(
                            "Keyboard Shortcuts",
                            comment: "Window menu item that opens the keyboard shortcuts window")
                    }
                )
                .keyboardShortcut(keyboardShortcutPanelShortcut?.shortcut)
            }
        }

        private func showWindow(_ id: String) {
            openWindow(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.forceFront(id)
            }
        }

        private var appInfoCommand: some Commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button(
                    action: {
                        openWindow(id: "about")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApp.forceFront("about")
                        }
                    },
                    label: {
                        Text(
                            "About Roam",
                            comment: "Button to open the about page of the Roam app")
                    })
            }
        }

        @CommandsBuilder
        private var pasteboardCommand: some Commands {
            if appDelegate.navigationPath.focusedWindow == .remote {
                CommandGroup(replacing: CommandGroupPlacement.pasteboard) {
                    PasteButton(
                        payloadType: String.self,
                        onPaste: { item in
                            Task {
                                guard let first = item.first else {
                                    Log.lifecycle.notice(
                                        "Failed to paste because no item in pasteboard")
                                    return
                                }
                                guard
                                    let texteditId = appDelegate.ecpMonitor.textEditStatus
                                        .texteditId
                                else {
                                    Log.lifecycle.notice(
                                        "Failed to paste because no textedit id")

                                    if let (app, params) = parsePastedUrl(first) {
                                        do {
                                            try await appDelegate.ecpMonitor.ecpClient?
                                                .launchApp(app, params: params)
                                        } catch {
                                            Log.lifecycle.error(
                                                "Error opening app from url app=\(app, privacy: .public) params=\(params, privacy: .public): \(error, privacy: .public)"
                                            )
                                        }
                                    }

                                    return
                                }

                                do {
                                    try await appDelegate.ecpMonitor.ecpClient?.setTextEdit(
                                        first, texteditId: texteditId)
                                } catch {
                                    Log.lifecycle.error(
                                        "Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        }
                    )
                    .customKeyboardShortcut(.paste)

                    Button(
                        "Cut", systemImage: "clipboard",
                        action: {
                            Task {
                                guard
                                    let texteditId = appDelegate.ecpMonitor.textEditStatus
                                        .texteditId
                                else {
                                    Log.lifecycle.notice(
                                        "Failed to paste because no textedit id")
                                    return
                                }

                                if let texteditText = appDelegate.ecpMonitor.textEditStatus.text
                                {
                                    Log.lifecycle.notice(
                                        "Cutting text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        texteditText, forType: .string)
                                }

                                do {
                                    try await appDelegate.ecpMonitor.ecpClient?.setTextEdit(
                                        "", texteditId: texteditId)
                                } catch {
                                    Log.lifecycle.error(
                                        "Failed to paste: \(error, privacy: .public)")
                                }
                            }
                        }
                    )
                    .customKeyboardShortcut(.cut)
                    .disabled(appDelegate.ecpMonitor.textEditStatus.texteditId == nil)

                    Button(
                        "Copy", systemImage: "clipboard",
                        action: {
                            Task {
                                if let texteditText = appDelegate.ecpMonitor.textEditStatus.text
                                {
                                    Log.lifecycle.notice(
                                        "Copying text \(texteditText, privacy: .public)")
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        texteditText, forType: .string)
                                }
                            }
                        }
                    )
                    .customKeyboardShortcut(.copy)
                    .disabled(appDelegate.ecpMonitor.textEditStatus.texteditId == nil)
                }
            }
        }

        @CommandsBuilder
        private var addDeviceCommand: some Commands {
            if appDelegate.navigationPath.focusedWindow == .settings
                || appDelegate.navigationPath.focusedWindow == .remote
            {
                CommandGroup(after: .appSettings) {
                    Divider()
                    Button("Add Device", systemImage: "plus") {
                        appDelegate.navigationPath.showAddDevice = true
                    }
                    .customKeyboardShortcut(.addDevice)
                }
            }
        }

        @CommandsBuilder
        private var refreshMessagesCommand: some Commands {
            if appDelegate.navigationPath.focusedWindow == .messages {
                CommandGroup(after: .appSettings) {
                    Divider()
                    Button("Refresh Chat Messages", systemImage: "arrow.clockwise.circle") {
                        appDelegate.refreshMessages()
                    }
                }
            }
        }

        private var helpCommand: some Commands {
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

        /// `showMenuBar`, but a write that merely echoes the current value is
        /// dropped instead of being forwarded to `UserDefaults`.
        ///
        /// `MenuBarExtra` treats `isInserted` as two-way and writes back through
        /// it while it reconciles the status item. `@AppStorage` forwards every
        /// write to `UserDefaults`, same-value ones included, and each one
        /// invalidates `body` for nothing. Genuine toggles (the user unchecking
        /// the preference) still write through.
        private var menuBarInserted: Binding<Bool> {
            let storage = self.$showMenuBar
            return Binding(
                get: { storage.wrappedValue },
                set: { newValue in
                    guard newValue != storage.wrappedValue else { return }
                    storage.wrappedValue = newValue
                }
            )
        }

        private var menuBarScene: some Scene {
            MenuBarExtra(
                "Roam Menu Bar", systemImage: "appletvremote.gen3",
                isInserted: self.menuBarInserted
            ) {
                // The 1.50/1.51 stack overflows died in this closure, building
                // the content value -- before `RemoteViewContained.body` ever
                // ran, so the probe there never got to fire. Measure here too.
                // swiftlint:disable:next redundant_discardable_let
                let _ = RenderTrace.body("macOS.MenuBarExtraContent")
                RemoteViewContained(isInMenuBar: true)
                    .menuBarPanelBackground()
                    .environmentObject(appDelegate)
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: NSApplication.willTerminateNotification)
                    ) { _ in
                        Log.lifecycle.notice("Shutting meuBar down from willTerminate")
                    }
                    .preferredColorScheme(.dark)
            }
            .menuBarExtraStyle(.window)
        }
    #endif

    var body: some Scene {
        #if os(macOS)
            mainWindowScene
            menuBarScene
        #else
            WindowGroup {
                RemoteView()
                    #if os(visionOS)
                        .frame(
                            width: inScreenshotTestingContext() ? macOSWidth : nil,
                            height: inScreenshotTestingContext() ? macOSHeigth : nil
                        )
                        .frame(minWidth: 400, minHeight: 950)
                        // visionOS's NavigationSplitView reads layout
                        // direction from the scene/window root, not from
                        // per-view environment overrides. Pin the whole
                        // window to LTR so the sidebar stays inline on the
                        // left and the detail pane actually renders in
                        // Arabic. Arabic text inside continues to display
                        // RTL via SwiftUI's bidi handling.
                        .environment(\.layoutDirection, .leftToRight)
                    #endif
                    #if os(iOS)
                        .task {
                            applyForceOrientationIfRequested()
                            applyMinimumWindowSizeIfNeeded()
                        }
                    #endif
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.willTerminateNotification)
                    ) { _ in
                        Log.lifecycle.notice("Shutting down from willTerminate")
                    }
                    .preferredColorScheme(.dark)
            }
            #if os(visionOS)
                .windowResizability(windowResizability)
                .defaultSize(width: visionOSWidth, height: 1000)
            #endif
        #endif

        #if os(macOS)
            Window(
                String(localized: "Messages", comment: "Window header for the messages window"),
                id: "messages"
            ) {
                MessageView()
                    .frame(width: 400)
                    .translucentBackground()
                    .removeToolbarTitle()
                    .onAppear {
                        NSApp.setActivationPolicyDeferred(.regular)
                        NSApp.forceFront("messages")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicyDeferred(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
            }
            .windowResizability(.contentSize)

            Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .onAppear {
                        NSApp.setActivationPolicyDeferred(.regular)
                        NSApp.forceFront("keyboard-shortcuts")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({
                            !$0.isExcludedFromWindowsMenu && $0.canBecomeKey && $0.isVisible
                        }).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicyDeferred(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
            }
            .windowResizability(.contentSize)
        #endif

        #if os(macOS)
            Settings {
                MacSettings()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .enableResize()
                    .onAppear {
                        NSApp.setActivationPolicyDeferred(.regular)
                    }
                    .onDisappear {
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicyDeferred(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
            }
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
                        NSApp.setActivationPolicyDeferred(.regular)
                        NSApp.forceFront("about")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicyDeferred(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
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

    #if os(iOS)
        @MainActor
        private func applyForceOrientationIfRequested() {
            let args = CommandLine.arguments
            let mask: UIInterfaceOrientationMask
            if args.contains("-ForceLandscapeLeft") {
                mask = .landscapeLeft
            } else if args.contains("-ForceLandscapeRight") {
                mask = .landscapeRight
            } else if args.contains("-ForceLandscape") {
                mask = .landscape
            } else if args.contains("-ForcePortrait") {
                mask = .portrait
            } else {
                return
            }
            // Xcode 26 iOS sim ignores XCUIDevice.shared.orientation when used from
            // UI tests - the canvas rotates but the app's scene geometry doesn't
            // follow. Drive the rotation app-side via requestGeometryUpdate so the
            // app's window relayouts even when XCTest's orientation handling is
            // broken. Used only under screenshot testing launch args.
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                return
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                Log.lifecycle.error("requestGeometryUpdate failed: \(error, privacy: .public)")
            }
        }
        @MainActor
        private func applyMinimumWindowSizeIfNeeded() {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene,
                    let restrictions = windowScene.sizeRestrictions
                else { continue }
                restrictions.minimumSize = CGSize(width: iPadMinWidth, height: iPadMinHeight)
            }
        }
        private var iPadMinWidth: CGFloat { 460 }
        private var iPadMinHeight: CGFloat { 782 }
    #endif

    // App Store Connect's APP_DESKTOP slot accepts 1280x800, 1440x900,
    // 2560x1600, or 2880x1800 (all 16:10 landscape). Force the main window
    // to 1440x900 logical points under UI-test context so XCUI's
    // window screenshot lands at 2880x1800 actual pixels on a retina display.
    var macOSWidth: CGFloat {
        if inUITestingContext() { return 1440 }
        return 760
    }

    var macOSHeigth: CGFloat {
        if inUITestingContext() { return 900 }
        return 680
    }

    var macOSMinWidth: CGFloat {
        return 360
    }

    var macOSMaxWidth: CGFloat {
        if inUITestingContext() { return 1440 }
        return 1100
    }

    var macOSMinHeight: CGFloat {
        return 640
    }

    var macOSMaxHeight: CGFloat {
        return 900
    }
}
