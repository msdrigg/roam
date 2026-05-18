#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// Self-screenshot driver for macOS App Store captures.
///
/// Triggered by the `-ScreenshotSavePath <file>` launch argument. Builds a
/// dedicated borderless NSWindow hosting the SwiftUI `RemoteView` (or
/// `MacSettings` when `-OpenSettings` is set), sized so its contentView is
/// 1440x900 logical points = 2880x1800 pixels on retina, which APP_DESKTOP
/// accepts. After `-ScreenshotSettleSeconds` (default 4s), it snapshots the
/// contentView's bitmap, writes the PNG to the requested path, and
/// terminates the app so the Python orchestrator can move on.
///
/// Why not use the production Window scene? macOS Roam pairs a `Window` with
/// a `MenuBarExtra`; the SwiftUI coexistence treats the app as
/// accessory-style and skips the main window's initial auto-show under
/// terminal/headless launches (no LaunchServices interaction). Forcing the
/// scene open requires private API. The dedicated NSWindow sidesteps all of
/// it — at the cost of NavigationSplitView's NSSplitView sidebar List not
/// fully realizing its content offscreen. Settings + the right-side remote
/// render correctly; the sidebar is white in Primary/ScreenScanning, which
/// is an acceptable trade-off for now.
enum MacScreenshotCapture {
    /// Logical content size that matches App Store Connect's APP_DESKTOP
    /// 2880x1800 acceptance on a retina display.
    private static let targetContentSize = NSSize(width: 1440, height: 900)

    /// Reads `-ScreenshotSavePath <path>` from the launch args. Returns nil
    /// if the flag is absent or has no value.
    static var requestedSavePath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-ScreenshotSavePath"),
              i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Reads `-ScreenshotSettleSeconds <secs>` from launch args. Defaults to
    /// 4.0s if missing or unparseable — enough for the test data store and
    /// the device sidebar to render in most locales.
    static var requestedSettleSeconds: Double {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-ScreenshotSettleSeconds"),
              i + 1 < args.count,
              let v = Double(args[i + 1]) else { return 4.0 }
        return v
    }

    /// Strong references survive past the .task autoreleasepool until the
    /// screenshot is taken.
    @MainActor private static var captureWindow: NSWindow?
    @MainActor private static var captureHosting: NSViewController?
    @MainActor private static var hasScheduled = false

    @MainActor
    static func scheduleIfRequested(appDelegate: RoamAppDelegate) {
        guard !hasScheduled else { return }
        guard let path = requestedSavePath else { return }
        hasScheduled = true
        let settle = requestedSettleSeconds
        let wantsSettings = CommandLine.arguments.contains("-OpenSettings")
        buildAndPresentWindow(appDelegate: appDelegate, wantsSettings: wantsSettings)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(settle))
            performAndExit(path: path)
        }
    }

    /// Constructs a borderless NSWindow with content size matching the
    /// APP_DESKTOP target. Hosts either RemoteView or MacSettings depending
    /// on launch state. Borderless avoids window chrome eating into the
    /// capture; the content view's bitmap is exactly 2880x1800 px on retina.
    @MainActor
    private static func buildAndPresentWindow(
        appDelegate: RoamAppDelegate, wantsSettings: Bool
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: targetContentSize),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.acceptsMouseMovedEvents = true

        let content: NSView
        if wantsSettings {
            let hosting = NSHostingController(
                rootView: AnyView(
                    ZStack {
                        Color.black.ignoresSafeArea()
                        MacSettings().environmentObject(appDelegate)
                    }
                    .preferredColorScheme(.dark)
                    .frame(width: targetContentSize.width, height: targetContentSize.height)
                )
            )
            captureHosting = hosting
            content = hosting.view
        } else {
            let hosting = NSHostingController(
                rootView: AnyView(
                    ZStack {
                        Color.black.ignoresSafeArea()
                        RemoteView().environmentObject(appDelegate)
                    }
                    .preferredColorScheme(.dark)
                    .frame(width: targetContentSize.width, height: targetContentSize.height)
                )
            )
            captureHosting = hosting
            content = hosting.view
        }
        content.frame = NSRect(origin: .zero, size: targetContentSize)
        window.contentView = content
        window.setContentSize(targetContentSize)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        // NavigationSplitView's sidebar uses NSTableView/NSSplitView under
        // the hood — `preferredColorScheme(.dark)` is a SwiftUI hint that
        // doesn't propagate into the underlying AppKit chrome. Force dark
        // appearance on the hosting view so the sidebar List background and
        // text colors match the rest of the dark capture.
        content.appearance = NSAppearance(named: .darkAqua)

        // Place fully inside the visible screen so NSScrollView /
        // NSTableView in NavigationSplitView's sidebar get a real layout
        // pass before we snapshot.
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - window.frame.height
            ))
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.display()
        captureWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private static func snapshot(_ view: NSView) -> Data? {
        // Force layout + display so any pending SwiftUI passes finalize
        // before snapshot.
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }

    @MainActor
    private static func performAndExit(path: String) {
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        }
        guard let window = captureWindow, let view = window.contentView else {
            FileHandle.standardError.write(
                Data("SCREENSHOT_ERROR: no capture window\n".utf8))
            return
        }
        guard let data = snapshot(view) else {
            FileHandle.standardError.write(
                Data("SCREENSHOT_ERROR: snapshot encoding failed\n".utf8))
            return
        }
        let url = resolveWritableURL(forRequested: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            FileHandle.standardOutput.write(
                Data("SCREENSHOT_WRITTEN: \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(
                Data("SCREENSHOT_ERROR: write failed \(error)\n".utf8))
        }
    }

    /// Resolve the final write destination. macOS Roam is sandboxed, so an
    /// absolute path like `/tmp/foo.png` will be denied. First try the
    /// literal requested path (works for paths inside the sandbox / data
    /// container, e.g. resolves relative paths to the container root). If
    /// the parent isn't writable, fall back to the app group container.
    private static func resolveWritableURL(forRequested path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let direct = URL(fileURLWithPath: expanded)
        let parent = direct.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parent.path) {
            return direct
        }
        let appGroup = "group.com.msdrigg.roam"
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            return container
                .appendingPathComponent("screenshots", isDirectory: true)
                .appendingPathComponent(direct.lastPathComponent)
        }
        return direct
    }
}
#endif
