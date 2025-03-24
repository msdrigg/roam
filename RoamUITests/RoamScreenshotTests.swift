import XCTest

final class RoamUITestsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() async throws {
        let locales = ["en-US", "fr-FR", "fr-CA", "de-DE", "it", "es-ES", "es-MX", "pt-PT", "pt-BR", "vi", "ar-SA", "zh-Hans"]

        for locale in locales {
            try await captureScreenshots(locale: Locale(identifier: locale))
        }
    }

#if os(iOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(locale.language.languageCode!.identifier))"]
        app.launchArguments += ["-AppleLocale", "\(locale.identifier)"]
        app.launchArguments += ["-SwiftDataTesting"]

        app.launch()

        let scanningAttachmentDark = XCTAttachment(screenshot: app.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-SwiftDataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCUIDevice.shared.orientation = .landscapeLeft

        // Wait for 0.8 s
        try await Task.sleep(nanoseconds: 800_000_000)

        let landscapeModeAttachment = XCTAttachment(screenshot: app.screenshot())
        landscapeModeAttachment.lifetime = .keepAlways
        landscapeModeAttachment.name = "\(locale.identifier)/3/LandscapePrimary"
        add(landscapeModeAttachment)

        XCUIDevice.shared.orientation = .portrait

        // Wait for 0.8 s
        try await Task.sleep(nanoseconds: 800_000_000)

        let primaryAttachment = XCTAttachment(screenshot: app.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        // Click on device picker
        app.buttons["KeyboardButton"].waitForClickable().tap()

        // Wait for 0.5 s
        try await Task.sleep(nanoseconds: 500_000_000)

        let kbAttachment = XCTAttachment(screenshot: app.screenshot())
        kbAttachment.lifetime = .keepAlways
        kbAttachment.name = "\(locale.identifier)/5/KeyboardOpen"
        add(kbAttachment)

        app.buttons["KeyboardButton"].waitForClickable().tap()
        app.buttons["DevicePickerTop"].waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let dpAttachment = XCTAttachment(screenshot: app.screenshot())
        dpAttachment.lifetime = .keepAlways
        dpAttachment.name = "\(locale.identifier)/6/DevicePickerOpen"
        add(dpAttachment)

        // Click on settings
        app.buttons["SettingsButton"].waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: app.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/7/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable().tap()

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
        app.launchArguments += ["-AppleLanguages", "(\(locale.language.languageCode!.identifier))"]
        app.launchArguments += ["-AppleLocale", "\(locale.identifier)"]
        app.launchArguments += ["-SwiftDataTesting"]
        print("Launching with args \(app.launchArguments)")

        app.launch()

        let scanningAttachmentDark = XCTAttachment(screenshot: app.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-SwiftDataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let primaryAttachment = XCTAttachment(screenshot: app.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        // Click on device picker
        app.buttons["KeyboardButton"].waitForClickable().tap()

        // Wait for 0.5 s
        try await Task.sleep(nanoseconds: 500_000_000)

        let kbAttachment = XCTAttachment(screenshot: app.screenshot())
        kbAttachment.lifetime = .keepAlways
        kbAttachment.name = "\(locale.identifier)/5/KeyboardOpen"
        add(kbAttachment)

        app.buttons["KeyboardButton"].waitForClickable().tap()
        app.buttons["DevicePickerTop"].waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let dpAttachment = XCTAttachment(screenshot: app.screenshot())
        dpAttachment.lifetime = .keepAlways
        dpAttachment.name = "\(locale.identifier)/6/DevicePickerOpen"
        add(dpAttachment)

        // Click on settings
        app.buttons["SettingsButton"].waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: app.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/7/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sIAttachment = XCTAttachment(screenshot: app.screenshot())
        sIAttachment.lifetime = .keepAlways
        sIAttachment.name = "\(locale.identifier)/8/SettingsItem"
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
#elseif os(macOS)
    @MainActor
    func captureScreenshots(locale: Locale) async throws {
        print("Capturing screenshot's for \(locale.identifier)")
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(locale.language.languageCode!.identifier))"]
        app.launchArguments += ["-AppleLocale", "\(locale.identifier)"]
        app.launchArguments += ["-SwiftDataTesting"]
        print("Launching with args \(app.launchArguments)")

        app.launch()

        let scanningAttachmentDark = XCTAttachment(screenshot: app.screenshot())
        scanningAttachmentDark.lifetime = .keepAlways
        scanningAttachmentDark.name = "\(locale.identifier)/4/ScreenScanning"
        add(scanningAttachmentDark)

        app.terminate()

        app.launchArguments += ["-SwiftDataLoadTestingData"]
        app.launchArguments += ["-ScreenshotTesting"]
        app.launch()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let primaryAttachment = XCTAttachment(screenshot: app.screenshot())
        primaryAttachment.lifetime = .keepAlways
        primaryAttachment.name = "\(locale.identifier)/1/Primary"
        add(primaryAttachment)

        app.menuButtons["DevicePickerTop"].firstMatch.waitForClickable().tap()

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let dpAttachment = XCTAttachment(screenshot: app.screenshot())
        dpAttachment.lifetime = .keepAlways
        dpAttachment.name = "\(locale.identifier)/5/DevicePickerOpen"
        add(dpAttachment)

        // Click on settings via keyboard shortcut
        app.menuButtons["DevicePickerTop"].firstMatch.waitForClickable().typeKey(XCUIKeyboardKey(","), modifierFlags: .command)

        // Wait for 0.3 s
        try await Task.sleep(nanoseconds: 300_000_000)

        let sAttachment = XCTAttachment(screenshot: app.screenshot())
        sAttachment.lifetime = .keepAlways
        sAttachment.name = "\(locale.identifier)/6/Settings"
        add(sAttachment)

        // Click on the first device
        app.buttons["DeviceItem_\(0)"].waitForClickable().tap()

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
    func waitForClickable(timeout: TimeInterval = 10) -> XCUIElement {
        #if os(visionOS)
        let predicate = NSPredicate(format: "exists == true")
        #else
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        #endif
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Button was not clickable within the timeout")
        }

        return self
    }
}
