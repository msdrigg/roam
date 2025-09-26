import XCTest

final class RoamWatchUITestsScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() async throws {
        let locales = ["ar-SA", "zh-Hans", "en-US", "fr-FR", "fr-CA", "de-DE", "it", "es-ES", "es-MX", "pt-PT", "pt-BR", "vi"]

        for locale in locales {
            try await captureScreenshots(locale: Locale(identifier: locale))
        }
    }

    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(locale.language.languageCode!.identifier))"]
        app.launchArguments += ["-AppleLocale", "\(locale.identifier)"]
        app.launchArguments += ["-DataTesting"]

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

        app.otherElements["MainTabView"].waitForClickable(app: app, testCase: self).swipeUp()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let secondaryAttachment = XCTAttachment(screenshot: app.screenshot())
        secondaryAttachment.lifetime = .keepAlways
        secondaryAttachment.name = "\(locale.identifier)/2/Secondary"
        add(secondaryAttachment)

        app.otherElements["MainTabView"].waitForClickable(app: app, testCase: self).swipeUp()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let appsAttachment = XCTAttachment(screenshot: app.screenshot())
        appsAttachment.lifetime = .keepAlways
        appsAttachment.name = "\(locale.identifier)/3/Apps"
        add(appsAttachment)

        let devicePickerButton = app.buttons["DevicePicker"].firstMatch

        let buttonFrame = devicePickerButton.frame
        let bottomMiddleX = buttonFrame.midX
        let bottomMiddleY = buttonFrame.maxY
        let bottomMiddleCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: bottomMiddleX, dy: bottomMiddleY))

        // Perform the tap at the calculated coordinate
        bottomMiddleCoordinate.tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let dpAttachment = XCTAttachment(screenshot: app.screenshot())
        dpAttachment.lifetime = .keepAlways
        dpAttachment.name = "\(locale.identifier)/5/DevicePickerOpen"
        add(dpAttachment)

        // Click on settings
        app.buttons["SettingsButton"].waitForClickable(app: app, testCase: self).tap()

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
    }
}

extension XCUIElement {
    func waitForClickable(timeout: TimeInterval = 10) -> XCUIElement {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Button was not clickable within the timeout")
        }

        return self
    }
}
