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

#if os(iOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Preserve the full BCP-47 identifier (e.g. fr-CA, en-GB) — passing
        // only the bare languageCode would lose the regional variant.
        app.launchArguments += ["-AppleLanguages", "(\(locale.identifier))"]
        // -AppleLocale expects NSLocale's underscore form (fr_CA, not fr-CA).
        app.launchArguments += ["-AppleLocale", locale.identifier.replacingOccurrences(of: "-", with: "_")]
        app.launchArguments += ["-DataTesting"]

        app.launch()

        let scanningAttachmentDark = XCTAttachment(screenshot: app.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-DataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]

        // Capture LandscapePrimary first, by setting orientation BEFORE launch.
        // iPad in Xcode 26 doesn't reliably re-layout when the orientation
        // changes mid-session — the canvas swaps to landscape dims but the
        // app's view stays portrait, producing a sideways-rotated capture.
        // Setting orientation pre-launch makes the app come up in landscape
        // from the start so the layout is correct.
        XCUIDevice.shared.orientation = .landscapeLeft
        try await Task.sleep(nanoseconds: 1_000_000_000)
        app.launch()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let landscapeModeAttachment = XCTAttachment(screenshot: app.screenshot())
        landscapeModeAttachment.lifetime = .keepAlways
        landscapeModeAttachment.name = "\(locale.identifier)/3/LandscapePrimary"
        add(landscapeModeAttachment)

        // Now back to portrait for the rest of the captures. Terminate +
        // relaunch ensures the app picks up the new orientation.
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        try await Task.sleep(nanoseconds: 1_000_000_000)
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let primaryAttachment = XCTAttachment(screenshot: app.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        // Open the keyboard.
        app.buttons["KeyboardButton"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.5 s
        try await Task.sleep(nanoseconds: 500_000_000)

        // First-time iOS keyboard usage may pop the QuickPath ("slide to type")
        // tutorial card on top of the keyboard. Dismiss it if present so the
        // capture shows the actual keyboard, not the iOS tutorial.
        let tutorialContinueButton = app.buttons["Continue"]
        if tutorialContinueButton.exists && tutorialContinueButton.isHittable {
            tutorialContinueButton.tap()
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let kbAttachment = XCTAttachment(screenshot: app.screenshot())
        kbAttachment.lifetime = .keepAlways
        kbAttachment.name = "\(locale.identifier)/5/KeyboardOpen"
        add(kbAttachment)

        // Close the keyboard to get back to the remote view, then go straight
        // to Settings. The new iOS UI uses a segmented Picker for device
        // selection (no separate "opened" state), so a dedicated
        // "DevicePickerOpen" capture is redundant with Primary.
        app.buttons["KeyboardButton"].waitForClickable(app: app, testCase: self).tap()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Click on settings
        app.buttons["SettingsButton"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: app.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/7/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sIAttachment = XCTAttachment(screenshot: app.screenshot())
        sIAttachment.lifetime = .keepAlways
        sIAttachment.name = "\(locale.identifier)/8/SettingsItem"
        add(sIAttachment)

        app.terminate()
    }
#elseif os(visionOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        // Preserve the full BCP-47 identifier (e.g. fr-CA, en-GB).
        app.launchArguments += ["-AppleLanguages", "(\(locale.identifier))"]
        // -AppleLocale expects NSLocale's underscore form (fr_CA, not fr-CA).
        app.launchArguments += ["-AppleLocale", locale.identifier.replacingOccurrences(of: "-", with: "_")]
        app.launchArguments += ["-DataTesting"]

        app.launch()

        // visionOS sim: app.screenshot() returns 1x1 placeholders. Use
        // XCUIScreen.main.screenshot() to capture the actual rendered window.
        let scanningAttachmentDark = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-DataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let primaryAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        // Skip the keyboard view + DevicePicker tap: the new UI's keyboard
        // doesn't surface a TextField on visionOS, and the segmented Picker
        // has no "opened" state. Go straight to Settings.
        app.buttons["SettingsButton"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/7/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sIAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sIAttachment.lifetime = .keepAlways
        sIAttachment.name = "\(locale.identifier)/8/SettingsItem"
        add(sIAttachment)

        app.terminate()
    }
#elseif os(macOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        // Preserve the full BCP-47 identifier (e.g. fr-CA, en-GB) — passing
        // only the bare languageCode would lose the regional variant.
        app.launchArguments += ["-AppleLanguages", "(\(locale.identifier))"]
        // -AppleLocale expects NSLocale's underscore form (fr_CA, not fr-CA).
        app.launchArguments += ["-AppleLocale", locale.identifier.replacingOccurrences(of: "-", with: "_")]
        app.launchArguments += ["-DataTesting"]
        print("Launching with args \(app.launchArguments)")

        app.launch()

        let scanningAttachmentDark = XCTAttachment(screenshot: app.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-DataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let primaryAttachment = XCTAttachment(screenshot: app.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        // The new UI uses a segmented Picker for device selection (no separate
        // "opened" state), so a dedicated "DevicePickerOpen" capture is
        // redundant with Primary. Skip directly to Settings via Cmd+, on the
        // frontmost window — no need for a focus target element.
        app.typeKey(",", modifierFlags: .command)

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: app.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/6/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable(app: app, testCase: self).tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sIAttachment = XCTAttachment(screenshot: app.screenshot())
        sIAttachment.lifetime = .keepAlways
        sIAttachment.name = "\(locale.identifier)/7/SettingsItem"
        add(sIAttachment)

        app.terminate()

        app.launchArguments += ["-WindowStyleVertical"]
        app.launch()
        try await Task.sleep(nanoseconds: 200_000_000)

        let landscapeModeAttachment = XCTAttachment(screenshot: app.screenshot())
        landscapeModeAttachment.lifetime = .keepAlways
        landscapeModeAttachment.name = "\(locale.identifier)/3/LandscapePrimary"
        add(landscapeModeAttachment)

        app.terminate()
    }
#endif

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
