import XCTest

final class CompanionTests: XCTestCase {
    @MainActor func testWidgetGalleryAndReviewLink() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["startRound"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.76)).press(forDuration: 1.6)
        let edit = board.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 4), board.debugDescription)
        edit.tap()
        let add = board.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Add Widget'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), board.debugDescription)
        add.tap()
        let search = board.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), board.debugDescription)
        search.tap()
        search.typeText("Cleaner 365")
        let result = board.cells["Cleaner 365"]
        XCTAssertTrue(result.waitForExistence(timeout: 6), board.debugDescription)
        result.tap()
        XCTAssertTrue(board.staticTexts["Season progress"].waitForExistence(timeout: 5), board.debugDescription)
        let shot = XCTAttachment(screenshot: board.screenshot())
        shot.name = "Season progress widget"; shot.lifetime = .keepAlways; self.add(shot)
        // Open the same review URL used by both widget sizes.
        app.open(URL(string: "cleaner365://review")!)
        XCTAssertTrue(app.staticTexts["roundProgress"].waitForExistence(timeout: 8))
    }
}
