//
//  RoamUITests.swift
//  RoamUITests
//
//  Created by Scott Driggers on 6/26/24.
//

import XCTest

final class RoamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    #if os(iOS)
    @MainActor
    func testDuoSidebarNavigation() throws {
        try XCTSkipUnless(UIDevice.current.name.contains("iPhone Duo"), "Requires an unfolded iPhone Duo")
        let app = navigationTestApp()
        app.launch()
        defer { app.terminate() }

        let sidebarToggle = app.buttons["SidebarButton"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["AllDevicesButton"].exists)
        XCTAssertTrue(app.buttons["SettingsButton"].exists)

        let devices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'SidebarDevice_'"))
        if !devices.firstMatch.exists {
            sidebarToggle.tap()
        }
        XCTAssertTrue(devices.element(boundBy: 1).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["AddDeviceButton"].exists)
        XCTAssertTrue(app.buttons["SortDevicesButton"].exists)
        let selectedId = devices.element(boundBy: 1).identifier
        app.buttons[selectedId].tap()
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: app.buttons[selectedId])
        waitForExpectations(timeout: 5)

        sidebarToggle.tap()
        XCTAssertTrue(app.buttons[selectedId].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["AllDevicesButton"].exists)
        sidebarToggle.tap()
        XCTAssertTrue(app.buttons[selectedId].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[selectedId].isSelected)
    }

    @MainActor
    func testCompactPhoneGridNavigation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires a phone")
        try XCTSkipIf(UIDevice.current.name.contains("iPhone Duo"), "Runs on a compact phone")
        let app = navigationTestApp()
        app.launch()
        defer { app.terminate() }

        let allDevices = app.buttons["AllDevicesButton"]
        XCTAssertTrue(allDevices.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["SidebarButton"].exists)
        allDevices.tap()

        let devices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'DeviceCard_'"))
        XCTAssertTrue(devices.element(boundBy: 1).waitForExistence(timeout: 10))
        devices.element(boundBy: 1).tap()
        XCTAssertTrue(allDevices.waitForExistence(timeout: 10))
        allDevices.tap()
        XCTAssertTrue(devices.element(boundBy: 1).waitForExistence(timeout: 10))
    }

    /// The delete confirmation must be an alert. A confirmationDialog replaces
    /// the open context menu in place, which crashed 1.65 on iOS 27.
    @MainActor
    func testDeviceCardDeleteConfirmsWithAlert() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires a phone")
        try XCTSkipIf(UIDevice.current.name.contains("iPhone Duo"), "Runs on a compact phone")
        let app = navigationTestApp()
        app.launch()
        defer { app.terminate() }

        let allDevices = app.buttons["AllDevicesButton"]
        XCTAssertTrue(allDevices.waitForExistence(timeout: 15))
        allDevices.tap()

        let devices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'DeviceCard_'"))
        XCTAssertTrue(devices.element(boundBy: 1).waitForExistence(timeout: 10))
        let countBefore = devices.count
        devices.element(boundBy: 1).press(forDuration: 1.2)

        let menuDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(menuDelete.waitForExistence(timeout: 5))
        menuDelete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()

        let removed = NSPredicate { _, _ in devices.count == countBefore - 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 10)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Opens and closes the keyboard entry until the app stops answering.
    /// 0x8BADF00D reports from 1.61 to 1.64 deadlock right as the entry's field
    /// takes first responder; a simulator has no watchdog, so a deadlock shows
    /// up here as the close button never appearing.
    @MainActor
    func testKeyboardEntryOpenCloseStress() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires a phone")
        let environment = ProcessInfo.processInfo.environment
        let iterations = Int(environment["KEYBOARD_STRESS_ITERATIONS"] ?? "") ?? 40
        let app = navigationTestApp()
        // The test-data flags clear the database first, which on a personal
        // device wipes its real devices and chat.
        if environment["KEYBOARD_STRESS_REAL_DATA"] == "1" {
            app.launchArguments = []
        }
        if environment["KEYBOARD_STRESS_GLASS"] == "1" {
            app.launchArguments.append("-StressAsyncGlass")
        }
        app.launch()
        defer { app.terminate() }

        let realData = environment["KEYBOARD_STRESS_REAL_DATA"] == "1"
        let keyboardButton = app.buttons["KeyboardButton"].firstMatch
        XCTAssertTrue(keyboardButton.waitForExistence(timeout: 15))

        for iteration in 0..<iterations {
            keyboardButton.tap()
            let closeButton = onscreenElement(app.buttons.matching(identifier: "CloseKeyboardButton"), in: app)
            XCTAssertTrue(
                closeButton.waitForExistence(timeout: 10),
                "Keyboard entry never appeared on iteration \(iteration)")
            // Real data means a real TV, which would receive the keystrokes.
            if iteration == 0 && !realData {
                let field = app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == 1")).firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                app.typeText("ok")
                XCTAssertEqual(field.value as? String, "ok")
            }
            closeButton.tap()
            XCTAssertTrue(
                keyboardButton.waitForExistence(timeout: 10),
                "Remote never came back on iteration \(iteration)")
        }
    }

    /// The pager keeps neighbouring pages alive, each with its own controls,
    /// so pick the match that is actually on screen.
    @MainActor
    private func onscreenElement(_ query: XCUIElementQuery, in app: XCUIApplication) -> XCUIElement {
        _ = query.firstMatch.waitForExistence(timeout: 10)
        let window = app.windows.firstMatch.frame
        for element in query.allElementsBoundByIndex
        where window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
            return element
        }
        return query.firstMatch
    }

    @MainActor
    private func navigationTestApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"]
        return app
    }
    #endif
}
