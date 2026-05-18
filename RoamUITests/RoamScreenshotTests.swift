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

        // 2. Primary (detail pager auto-opens to first device).
        let primaryApp = XCUIApplication()
        appendLocaleArgs(primaryApp, locale: locale)
        primaryApp.launchArguments += ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"]
        primaryApp.launch()
        try await Task.sleep(nanoseconds: 2_500_000_000)
        addScreenshot(primaryApp.screenshot(), name: "\(locale.identifier)/1/Primary")

        // 3. Tap "All devices" button to navigate back to the home grid.
        let allDevicesButton = primaryApp.buttons["AllDevicesButton"]
        if allDevicesButton.waitForExistence(timeout: 5) && allDevicesButton.isHittable {
            allDevicesButton.tap()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            addScreenshot(
                primaryApp.screenshot(), name: "\(locale.identifier)/2/Home"
            )
        } else {
            print("AllDevicesButton not hittable — skipping Home capture")
        }

        // 4. Tap "Settings" from the home grid bottom bar to push the
        //    settings sheet, capture it.
        let settingsButton = primaryApp.buttons["SettingsButton"]
        if settingsButton.waitForExistence(timeout: 5) && settingsButton.isHittable {
            settingsButton.tap()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            addScreenshot(
                primaryApp.screenshot(), name: "\(locale.identifier)/7/Settings"
            )
        } else {
            print("SettingsButton not hittable — skipping Settings capture")
        }

        primaryApp.terminate()

        // 5. Landscape primary — relaunch with -ForceLandscapeLeft so the
        //    app drives the rotation via UIWindowScene.requestGeometryUpdate
        //    (XCUIDevice.shared.orientation is a no-op on Xcode 26 sims).
        let landscapeApp = XCUIApplication()
        appendLocaleArgs(landscapeApp, locale: locale)
        landscapeApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
            "-ForceLandscapeLeft",
        ]
        landscapeApp.launch()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        // XCUIScreen.main.screenshot() returns the actual rendered framebuffer
        // (post-rotation if the simulator honored requestGeometryUpdate). The
        // Python orchestrator handles any necessary post-rotation to satisfy
        // App Store Connect's landscape pixel-dim requirement.
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
        try await Task.sleep(nanoseconds: 2_500_000_000)
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
        try await Task.sleep(nanoseconds: 3_000_000_000)
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
        try await Task.sleep(nanoseconds: 2_000_000_000)
        addScreenshot(settingsApp.screenshot(), name: "\(locale.identifier)/7/Settings")
        settingsApp.terminate()

        // 5. Landscape primary — for the iPad we also rely on the existing
        //    iPadOS sim rotation workaround in scripts/sync-metadata.py.
        let landscapeApp = XCUIApplication()
        appendLocaleArgs(landscapeApp, locale: locale)
        landscapeApp.launchArguments += [
            "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
        ]
        XCUIDevice.shared.orientation = .landscapeLeft
        landscapeApp.launch()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        addScreenshot(
            landscapeApp.screenshot(),
            name: "\(locale.identifier)/3/LandscapePrimary"
        )
        landscapeApp.terminate()
        XCUIDevice.shared.orientation = .portrait
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
