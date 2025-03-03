#if os(macOS)
import AppKit
import OSLog

// TODO: This isn't working, how to get nsresponder chain events??
final class GimmikScalarDelegate: NSWindowController, NSWindowDelegate {
    let delegate: (any NSWindowDelegate)?
    let controller: NSWindowController?

    let id: String = UUID().uuidString
    var isWindowResizing: Bool = false

    var isMinWidthReached: Bool = false
    var isMinHeightReached: Bool = false

    var minWidthFrame: NSRect?
    var minHeightFrame: NSRect?

    var minWidthMouse: NSPoint?
    var minHeightMouse: NSPoint?

    var scaleX: CGFloat = 3
    var scaleY: CGFloat = 3

    init(controller: NSWindowController?, delegate: (any NSWindowDelegate)?, window: NSWindow) {
        self.delegate = delegate
        self.controller = controller

        super.init(window: window)
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func checkPosition(_ window: NSWindow) {
        let frame = window.frame

        if self.isMinWidthReached {
            if frame.width > window.minSize.width {
                self.isMinWidthReached = false
            }
        } else if frame.width == window.minSize.width {
            self.isMinWidthReached = true
            self.minWidthFrame = frame
            self.minWidthMouse = NSEvent.mouseLocation
        }

        if self.isMinHeightReached {
            if frame.height > window.minSize.height {
                self.isMinHeightReached = false
            }
        } else if frame.height == window.minSize.height {
            self.isMinHeightReached = true
            self.minHeightFrame = frame
            self.minHeightMouse = NSEvent.mouseLocation
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        Log.userInteraction.notice("Window did end live resize and stop tracking mousemove")
        self.isWindowResizing = false
    }

    override func mouseDragged(with event: NSEvent) {
        Log.userInteraction.notice("Dragggged info")
        if let window, self.isWindowResizing {
            self.checkPosition(window)

            guard let window = self.window else {
                Log.userInteraction.error("No window in mouseDragged")
                return
            }

            Log.userInteraction.notice("Dragggged")
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        Log.userInteraction.notice("Window did start live resize and start tracking mousemove")
        self.isWindowResizing = true
        guard let window = notification.object as? NSWindow else {
            Log.userInteraction.error("No window in notification for start live resize")
            return
        }

        self.checkPosition(window)
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            Log.userInteraction.notice("Got local event")
            return event
        }

//        while self.isWindowResizing {
//            guard let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) else {
//                Log.userInteraction.notice("Not getting loop event")
//                break
//            }
//            Log.userInteraction.notice("Got loop event \(e.type.rawValue) \(e.deltaX) \(e.deltaY)")
//            window.postEvent(e, atStart: true)
//            guard e.type != .leftMouseUp else {
//                self.isWindowResizing = false
//                Log.userInteraction.notice("Breaking")
//                break
//            }
//            self.checkPosition(window)
//
//            guard let minWidthMouse, let minHeightMouse, let minWidthFrame, let minHeightFrame else {
//                continue
//            }
//
//            guard e.type == .leftMouseDragged else {
//                continue
//            }
//
//            let damp: (CGFloat) -> CGFloat = { delta in
//                return copysign(3.0 * log(pow(abs(delta) / 30.0 + 1.0, 5.0)), delta)
//            }
//
//            let mouseDeltaX = NSEvent.mouseLocation.x - minWidthMouse.x
//            let mouseDeltaY = NSEvent.mouseLocation.y - minHeightMouse.y
//            let minWidthFrameX = minWidthFrame.minX
//            let minHeightFrameY = minHeightFrame.minY
//            let dampedX = minWidthFrameX + self.scaleX * damp(mouseDeltaX)
//            let dampedY = minHeightFrameY + self.scaleY * damp(mouseDeltaY)
//
//            window.setFrame(NSRect(
//                x: dampedX,
//                y: dampedY,
//                width: window.frame.width,
//                height: window.frame.height
//            ), display: true)
//        }
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        self.controller?.windowTitle(forDocumentDisplayName: displayName) ?? super.windowTitle(forDocumentDisplayName: displayName)
    }

    override func windowWillLoad() {
        if let controller {
            controller.windowWillLoad()
        } else {
            super.windowWillLoad()
        }
    }

    override func windowDidLoad() {
        if let controller {
            controller.windowDidLoad()
        } else {
            super.windowDidLoad()
        }
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        return delegate?.windowWillReturnFieldEditor?(sender, to: client)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        Log.userInteraction.notice("Window will resize")
        return delegate?.windowWillResize?(sender, to: frameSize) ?? frameSize
    }
    func windowDidResize(_ notification: Notification) {
        Log.userInteraction.notice("Window did resize")
        delegate?.windowDidResize?(notification)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        return delegate?.windowWillUseStandardFrame?(window, defaultFrame: newFrame) ?? newFrame
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return delegate?.windowShouldZoom?(window, toFrame: newFrame) ?? true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return delegate?.windowWillReturnUndoManager?(window)
    }

    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        return delegate?.window?(window, willPositionSheet: sheet, using: rect) ?? rect
    }

    func window(_ window: NSWindow, shouldPopUpDocumentPathMenu menu: NSMenu) -> Bool {
        return delegate?.window?(window, shouldPopUpDocumentPathMenu: menu) ?? true
    }

    func window(_ window: NSWindow, shouldDragDocumentWith event: NSEvent, from dragImageLocation: NSPoint, with pasteboard: NSPasteboard) -> Bool {
        return delegate?.window?(window, shouldDragDocumentWith: event, from: dragImageLocation, with: pasteboard) ?? true
    }

    func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
        return delegate?.window?(window, willUseFullScreenContentSize: proposedSize) ?? proposedSize
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        return delegate?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
    }

    func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
        return delegate?.customWindowsToEnterFullScreen?(for: window)
    }

    func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenWithDuration duration: TimeInterval) {
        delegate?.window?(window, startCustomAnimationToEnterFullScreenWithDuration: duration)
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        delegate?.windowDidFailToEnterFullScreen?(window)
    }

    func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
        return delegate?.customWindowsToExitFullScreen?(for: window)
    }

    func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
        delegate?.window?(window, startCustomAnimationToExitFullScreenWithDuration: duration)
    }

    func customWindowsToEnterFullScreen(for window: NSWindow, on screen: NSScreen) -> [NSWindow]? {
        return delegate?.customWindowsToEnterFullScreen?(for: window, on: screen)
    }

    func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
        delegate?.window?(window, startCustomAnimationToEnterFullScreenOn: screen, withDuration: duration)
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        delegate?.windowDidFailToExitFullScreen?(window)
    }

    func window(_ window: NSWindow, willResizeForVersionBrowserWithMaxPreferredSize maxPreferredFrameSize: NSSize, maxAllowedSize maxAllowedFrameSize: NSSize) -> NSSize {
        return delegate?.window?(window, willResizeForVersionBrowserWithMaxPreferredSize: maxPreferredFrameSize, maxAllowedSize: maxAllowedFrameSize) ?? maxPreferredFrameSize
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        delegate?.window?(window, willEncodeRestorableState: state)
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        delegate?.window?(window, didDecodeRestorableState: state)
    }

    func previewRepresentableActivityItems(for window: NSWindow) -> [any NSPreviewRepresentableActivityItem]? {
        return delegate?.previewRepresentableActivityItems?(for: window)
    }

    func windowDidExpose(_ notification: Notification) {
        delegate?.windowDidExpose?(notification)
    }

    func windowWillMove(_ notification: Notification) {
        Log.userInteraction.notice("Window will move?")
        delegate?.windowWillMove?(notification)
    }

    func windowDidMove(_ notification: Notification) {
        Log.userInteraction.notice("Window did move?")
        delegate?.windowDidMove?(notification)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        delegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        delegate?.windowDidResignKey?(notification)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        delegate?.windowDidBecomeMain?(notification)
    }

    func windowDidResignMain(_ notification: Notification) {
        delegate?.windowDidResignMain?(notification)
    }

    func windowForSharingRequest(from window: NSWindow) -> NSWindow? {
        if #available(macOS 15.0, *) {
            return delegate?.windowForSharingRequest?(from: window)
        } else {
            return nil
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        delegate?.windowDidChangeOcclusionState?(notification)
    }

    func windowWillClose(_ notification: Notification) {
        Log.userInteraction.notice("Window will close")
        if let delegate, let window = notification.object as? NSWindow {
            Log.userInteraction.notice("Setting delegate on proxy")
            window.delegate = delegate
        }
        delegate?.windowWillClose?(notification)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Log.userInteraction.notice("Window should close")
        if let delegate {
            sender.delegate = delegate
        }

        return delegate?.windowShouldClose?(sender) ?? true
    }
}
#endif
