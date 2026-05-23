import XCTest

final class RoamUITestsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() async throws {
        let env = ProcessInfo.processInfo.environment
        let locale = env["SCREENSHOT_LOCALE"]
            ?? env["TEST_RUNNER_SCREENSHOT_LOCALE"]
            ?? "en-US"
        print("Capturing screenshots for locale \(locale)")
        try await captureScreenshots(locale: Locale(identifier: locale))
    }

    // MARK: - Common helpers

    /// `-AppleLanguages` needs the BCP-47 form in parens (`(fr-CA)`);
    /// `-AppleLocale` expects NSLocale's underscore form (`fr_CA`).
    private func appendLocaleArgs(_ app: XCUIApplication, locale: Locale) {
        app.launchArguments += ["-AppleLanguages", "(\(locale.identifier))"]
        app.launchArguments += [
            "-AppleLocale",
            locale.identifier.replacingOccurrences(of: "-", with: "_"),
        ]
    }

#if os(iOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.orientation = .portrait

        if UIDevice.current.userInterfaceIdiom == .pad {
            try await captureIPadScreenshots(locale: locale)
        } else {
            try await captureIPhoneScreenshots(locale: locale)
        }
    }

    // MARK: - iPhone

    @MainActor
    private func captureIPhoneScreenshots(locale: Locale) async throws {
        // 1. Empty-state ScreenScanning capture (no loaded test data).
        let scanningApp = XCUIApplication()
        appendLocaleArgs(scanningApp, locale: locale)
        scanningApp.launchArguments += ["-DataTesting"]
        scanningApp.launch()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        addScreenshot(scanningApp.screenshot(), name: "\(locale.identifier)/4/ScreenScanning")
        scanningApp.terminate()

        // 2. Primary (detail pager auto-opens to first device). The settle
        //    covers: blocking data load → PhoneHomeView appear → 150ms
        //    auto-push delay → .zoom push animation → PhoneDetailPage's
        //    DeviceLoader populating the per-page device. On a cold
        //    first launch the chain takes ~5s; shorter waits leave
        //    selectedDevice nil and render the remote in its disabled
        //    (grey) state with no device-name header.
        let primaryApp = XCUIApplication()
        appendLocaleArgs(primaryApp, locale: locale)
        primaryApp.launchArguments += ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"]
        primaryApp.launch()
        try await Task.sleep(nanoseconds: 7_000_000_000)
        addScreenshot(primaryApp.screenshot(), name: "\(locale.identifier)/1/Primary")

        // 3. Tap "All devices" button to navigate back to the home grid.
        //    The `.zoom` navigation pop animation takes ~0.4s; wait
        //    2.5s past the tap so the home grid has fully settled and we
        //    don't capture a half-zoomed device card.
        let allDevicesButton = primaryApp.buttons["AllDevicesButton"]
        if allDevicesButton.waitForExistence(timeout: 5) && allDevicesButton.isHittable {
            allDevicesButton.tap()
            try await Task.sleep(nanoseconds: 2_500_000_000)
            addScreenshot(
                primaryApp.screenshot(), name: "\(locale.identifier)/2/Home"
            )
        } else {
            print("AllDevicesButton not hittable — skipping Home capture")
        }

        primaryApp.terminate()

        // 4. Settings — relaunch with -OpenSettings so RemoteRoot's
        //    `applyLaunchSettingsIfRequested` pushes the Settings sheet on
        //    first appear. Driving the bottom-bar SettingsButton via XCUI
        //    was unreliable on the 6.5" iPhone 11 sim (the chain of
        //    Primary → AllDevicesButton → SettingsButton occasionally lost
        //    the sheet behind animations) — the launch arg always works.
        let settingsApp = XCUIApplication()
        appendLocaleArgs(settingsApp, locale: locale)
        settingsApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-OpenSettings",
        ]
        settingsApp.launch()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        addScreenshot(
            settingsApp.screenshot(), name: "\(locale.identifier)/7/Settings"
        )
        settingsApp.terminate()

        // 5. Keyboard open — relaunch with -OpenKeyboard so the
        //    PhoneDeviceDetailPager auto-shows the keyboard entry text
        //    field from first appear (and the system software keyboard
        //    follows because the TextField becomes first responder).
        //    Driving the toolbar/floating keyboard button via XCUI is
        //    brittle under non-en locales — the launch arg is reliable.
        let keyboardApp = XCUIApplication()
        appendLocaleArgs(keyboardApp, locale: locale)
        keyboardApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-OpenKeyboard",
        ]
        keyboardApp.launch()
        try await Task.sleep(nanoseconds: 4_000_000_000)
        addScreenshot(
            keyboardApp.screenshot(), name: "\(locale.identifier)/5/KeyboardOpen"
        )
        keyboardApp.terminate()

        // 6. Landscape primary — relaunch with -ForceLandscapeLeft so the
        //    app drives the rotation via UIWindowScene.requestGeometryUpdate
        //    (XCUIDevice.shared.orientation is a no-op on Xcode 26 sims).
        //    Capture via XCUIScreen.main.screenshot() which writes the
        //    device-native framebuffer (always portrait pixel dims). The
        //    Python orchestrator post-rotates the PNG 90° CW to satisfy
        //    App Store Connect's landscape dim requirement.
        //
        //    `simctl io booted screenshot` was tried as a "real landscape"
        //    capture, but the device framebuffer stays portrait regardless
        //    of how the Simulator window is rotated — the rotation only
        //    affects the host window's visual presentation, not the
        //    captured pixels.
        let landscapeApp = XCUIApplication()
        appendLocaleArgs(landscapeApp, locale: locale)
        landscapeApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-ForceLandscapeLeft",
        ]
        landscapeApp.launch()
        try await Task.sleep(nanoseconds: 5_000_000_000)
        addScreenshot(
            XCUIScreen.main.screenshot(),
            name: "\(locale.identifier)/3/LandscapePrimary"
        )
        landscapeApp.terminate()
    }

    // MARK: - iPad

    @MainActor
    private func captureIPadScreenshots(locale: Locale) async throws {
        // 1. ScreenScanning — empty sidebar + scanning state.
        let scanningApp = XCUIApplication()
        appendLocaleArgs(scanningApp, locale: locale)
        scanningApp.launchArguments += ["-DataTesting"]
        scanningApp.launch()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        addScreenshot(
            scanningApp.screenshot(), name: "\(locale.identifier)/4/ScreenScanning"
        )
        scanningApp.terminate()

        // 2. Primary remote with sidebar populated.
        let primaryApp = XCUIApplication()
        appendLocaleArgs(primaryApp, locale: locale)
        primaryApp.launchArguments += ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"]
        primaryApp.launch()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        addScreenshot(primaryApp.screenshot(), name: "\(locale.identifier)/1/Primary")
        primaryApp.terminate()

        // 3. Keyboard open — relaunch with -OpenKeyboard so the keyboard
        //    overlay is up from first appear. Driving via the toolbar
        //    button is flaky on the iPad sim under non-en locales.
        let keyboardApp = XCUIApplication()
        appendLocaleArgs(keyboardApp, locale: locale)
        keyboardApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-OpenKeyboard",
        ]
        keyboardApp.launch()
        try await Task.sleep(nanoseconds: 4_000_000_000)
        addScreenshot(keyboardApp.screenshot(), name: "\(locale.identifier)/5/KeyboardOpen")
        keyboardApp.terminate()

        // 4. Settings — relaunch with -OpenSettings to surface the
        //    Settings sheet on appear.
        let settingsApp = XCUIApplication()
        appendLocaleArgs(settingsApp, locale: locale)
        settingsApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-OpenSettings",
        ]
        settingsApp.launch()
        try await Task.sleep(nanoseconds: 2_500_000_000)
        addScreenshot(settingsApp.screenshot(), name: "\(locale.identifier)/7/Settings")
        settingsApp.terminate()

        // 5. Landscape primary — captured by the Python orchestrator via
        //    `simctl io booted screenshot` after rotating the booted sim
        //    through Simulator.app's Device → Orientation → Landscape Left
        //    menu (sent via osascript). On Xcode 26 iPad sims:
        //      - XCUIDevice.shared.orientation is a no-op.
        //      - requestGeometryUpdate(.landscapeLeft) returns success but
        //        the iPad scene stays portrait because the iPad app isn't
        //        UIRequiresFullScreen — orientation is system-controlled.
        //      - A system-side menu rotation DOES change the scene, and
        //        Roam's Info.plist supports all 4 orientations so it
        //        responds with a real landscape layout.
        //    Nothing to do from the test side.
    }

#elseif os(visionOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        // visionOS captures are driven via `simctl io screenshot` from the
        // Python orchestrator (XCTest's screenshot APIs return 1x1
        // placeholders on the visionOS sim). This test is a no-op kept so
        // the test bundle still has a target on visionOS.
        print("Skipping XCTest captures for visionOS \(locale.identifier) — handled by simctl")
    }

#elseif os(macOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        // macOS captures are driven directly by the app via the
        // `-ScreenshotSavePath` launch arg (see scripts/sync-metadata.py and
        // Roam/ScreenshotCapture.swift). The XCTest path is bypassed because
        // xcodebuild reliably hangs after macOS UI tests and XCUI can't
        // reach the app's window from the headless test runner.
        print("Skipping XCTest captures for macOS \(locale.identifier) — handled by app self-capture")
    }
#endif

    // MARK: - Attachment

    private func addScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}

extension XCUIElement {
    func waitForClickable(timeout: TimeInterval = 10, app: XCUIApplication, testCase: XCTestCase) -> XCUIElement {
        #if os(visionOS)
        let predicate = NSPredicate(format: "exists == true")
        #else
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        #endif
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            let debugAttachment = XCTAttachment(string: app.debugDescription)
            debugAttachment.lifetime = .keepAlways
            debugAttachment.name = "FailingAttachment"
            XCTestCase().add(debugAttachment)
            XCTFail("Button was not clickable within the timeout")
        }

        return self
    }
}
