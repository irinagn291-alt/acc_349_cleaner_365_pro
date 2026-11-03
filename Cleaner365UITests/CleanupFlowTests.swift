import Photos
import XCTest

final class CleanupFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testCollectionsAndSharedBin() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VaultMotion", withExtension: "jpg"))
        let original = try Data(contentsOf: url)
        let tag = Array(UUID().uuidString.utf8)
        // A valid JPEG comment gives this run an independent byte-identical pair.
        let fixture = original.prefix(2) + Data([0xff, 0xfe, 0x00, UInt8(tag.count + 2)] + tag) + original.dropFirst(2)
        var ids: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for _ in 0..<2 {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: fixture, options: nil)
                ids.append(request.placeholderForCreatedAsset!.localIdentifier)
            }
        }
        let app = XCUIApplication()
        app.launch()
        _ = app.buttons["startRound"].waitForExistence(timeout: 8)
        capture("Today", app)
        app.buttons["openCleanup"].tap()
        for title in ["Exact duplicates", "Screenshots", "Screen recordings", "Large videos"] {
            XCTAssertTrue(app.buttons["collection-" + title].waitForExistence(timeout: 8))
        }
        capture("Cleanup", app)
        app.buttons["collection-Large videos"].tap()
        XCTAssertTrue(app.staticTexts["100 MB or larger · biggest first"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["collection-Exact duplicates"].tap()
        let extras = app.buttons["Select extra copies"]
        XCTAssertTrue(extras.waitForExistence(timeout: 30))
        extras.tap()
        let queue = app.buttons["queueCollection"]
        XCTAssertTrue(queue.isEnabled)
        XCTAssertTrue(app.buttons["Deselect all"].exists)
        capture("Duplicate selection", app)
        // Select a test-created asset only; never queue or delete other files.
        app.buttons["Deselect all"].tap()
        for _ in 0..<15 {
            if let choice = ids.map({ app.buttons["select-" + $0] }).first(where: { $0.exists && $0.isHittable && $0.isEnabled }) {
                choice.tap()
                XCTAssertTrue(queue.isEnabled)
                queue.tap()
                XCTAssertTrue(app.staticTexts["1 added to your review bin."].waitForExistence(timeout: 5) || app.staticTexts["queueFeedback"].label == "1 added to your review bin.")
                app.buttons["collectionBin"].tap()
                XCTAssertTrue(app.staticTexts["binCount"].waitForExistence(timeout: 6))
                return
            }
            app.swipeUp()
        }
        XCTFail("The pair created by this test did not appear in the duplicate collection.")
    }

    func testOptInAndRemoveQuietReminder() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        let app = XCUIApplication()
        app.launch()
        app.buttons["Reminders"].tap()
        let toggle = app.switches["monthlyReminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wasOn = toggle.value as? String == "1"
        if wasOn { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        let off = NSPredicate(format: "value == '0' AND enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: off, object: toggle)], timeout: 5), .completed)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Allow|Разрешить")).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let on = NSPredicate(format: "value == '1' AND enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: toggle)], timeout: 6), .completed)
        if !wasOn {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: off, object: toggle)], timeout: 5), .completed)
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
