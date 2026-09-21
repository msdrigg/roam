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

    @MainActor
    private func navigationTestApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"]
        return app
    }
    #endif
}
