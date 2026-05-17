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

    var metricManager = RoamMetricManager()
    init() {
        Log.lifecycle.notice("Starting Roam")
        #if !os(macOS)
            installAborter()
        #endif
        installSIGPIPEHandler()

        #if !os(macOS)
            let dontKillAssertion = QActivityRunInBackgroundAssertion(name: "Tips.configure")
            if dontKillAssertion.isReleased() {
                return
            }
            defer {
                dontKillAssertion.release()
            }
        #endif
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.groupContainer(identifier: mainAppGroup)),
        ])
        RoamDataHandler.initializeSharedBlocking()
        migrateOffSwiftData()
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

    var body: some Scene {
        #if os(macOS)
            Window("Roam", id: "main") {
                RemoteView()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .removeToolbarBackground()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("main")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: NSApplication.willTerminateNotification)
                    ) { _ in
                        Log.lifecycle.notice("Shutting down main body from willTerminate")
                    }
                    .frame(
                        minWidth: macOSMinWidth,
                        idealWidth: macOSWidth,
                        maxWidth: macOSMaxWidth,
                        minHeight: macOSMinHeight,
                        idealHeight: macOSHeigth,
                        maxHeight: macOSMaxHeight
                    )
                    .preferredColorScheme(.dark)
            }
            .keyboardShortcut(showRoamShortcut?.shortcut)
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
            .commands {
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

                if appDelegate.navigationPath.focusedWindow == .messages {
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

            MenuBarExtra(
                "Roam Menu Bar", systemImage: "appletvremote.gen3", isInserted: self.$showMenuBar
            ) {
                RemoteViewContained(isInMenuBar: true)
                    .environmentObject(appDelegate)
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
        #else
            WindowGroup {
                RemoteView()
                    #if os(visionOS)
                        .frame(
                            width: inScreenshotTestingContext() ? macOSWidth : nil,
                            height: inScreenshotTestingContext() ? macOSHeigth : nil
                        )
                        .frame(minWidth: 400, minHeight: 950)
                    #endif
                    #if os(iOS)
                        .task {
                            applyForceOrientationIfRequested()
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
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("messages")
                    }
                    .onDisappear {
                        // If there is only one window left (this one), then revert to .accessory app
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
            }
            .keyboardShortcut(messagesShortcut?.shortcut)
            .windowResizability(.contentSize)

            Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("keyboard-shortcuts")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({
                            !$0.isExcludedFromWindowsMenu && $0.canBecomeKey && $0.isVisible
                        }).count <= 1 && showMenuBar {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                    .preferredColorScheme(.dark)
            }
            .keyboardShortcut(keyboardShortcutPanelShortcut?.shortcut)
            .windowResizability(.contentSize)
        #endif

        #if os(macOS)
            Settings {
                MacSettings()
                    .translucentBackground()
                    .removeToolbarTitle()
                    .enableResize()
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                    }
                    .onDisappear {
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicy(.accessory)
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
                        NSApp.setActivationPolicy(.regular)
                        NSApp.forceFront("about")
                    }
                    .onDisappear {
                        if NSApp.windows.filter({ $0.level != .statusBar && $0.isVisible }).count
                            <= 1 && showMenuBar
                        {
                            NSApp.setActivationPolicy(.accessory)
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
        // UI tests — the canvas rotates but the app's scene geometry doesn't
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
        return 560
    }

    var macOSMaxWidth: CGFloat {
        if inUITestingContext() { return 1440 }
        return 1100
    }

    var macOSMinHeight: CGFloat {
        return 560
    }

    var macOSMaxHeight: CGFloat {
        return 900
    }
}
