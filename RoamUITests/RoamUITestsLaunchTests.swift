//
//  RoamUITestsLaunchTests.swift
//  RoamUITests
//
//  Created by Scott Driggers on 6/26/24.
//

import XCTest

final class RoamUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        // Orient the device, light/dark theme, navigate to proper page, execute screenshot

        // Insert steps here to perform after app launch but before taking a screenshot

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
