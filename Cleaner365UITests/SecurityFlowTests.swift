import XCTest

final class SecurityFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openSecurity() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["openSecurity"]
        XCTAssertTrue(entry.waitForExistence(timeout: 6))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        return app
    }

    func testToolsFromHomeAndAliasSetup() {
        let app = openSecurity()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Security"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["securityTool-0"].tap()
        let output = app.staticTexts["generatedPassword"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let first = output.label
        XCTAssertEqual(first.count, 24)
        app.buttons["generatePassword"].tap()
        XCTAssertNotEqual(first, output.label)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["securityTool-1"].tap()
        XCTAssertTrue(app.secureTextFields["aliasKey"].exists)
        XCTAssertFalse(app.buttons["connectAliases"].isEnabled)
    }

    func testPublicPasswordLookupHandlesTheNetworkBeingOffline() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        let app = openSecurity()
        app.buttons["securityTool-3"].tap()
        XCTAssertFalse(app.buttons["checkPassword"].isEnabled)
        let password = app.secureTextFields["breachPassword"]
        password.tap()
        password.typeText("password\n")
        let exposed = app.staticTexts["Password exposed"]
        let failure = app.staticTexts["breachError"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            exposed.exists || failure.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 35), .completed)
        if failure.exists {
            XCTAssertEqual(failure.label, "Could not reach the service. Check your connection and try again.")
            XCTAssertFalse(app.staticTexts["No match found"].exists)
        }
    }

    func testEmailOpensOfficialResultsForPublicExample() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        let app = openSecurity()
        app.buttons["securityTool-2"].tap()
        XCTAssertFalse(app.buttons["checkEmail"].isEnabled)
        let email = app.textFields["breachEmail"]
        email.tap()
        email.typeText("account-exists@hibp-integration-tests.com\n")
        let browser = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "haveibeenpwned.com")).firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 20), app.debugDescription)
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "HIBP email lookup"; sheet.lifetime = .keepAlways; add(sheet)
    }
}
