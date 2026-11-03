import XCTest
import Photos

final class RoundTripTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHomeOpensBin() {
        let app = XCUIApplication()
        app.launch()
        let bin = app.buttons["openBin"]
        XCTAssertTrue(bin.waitForExistence(timeout: 10))
        if !bin.isHittable { app.swipeUp() }
        bin.tap()
        XCTAssertTrue(app.staticTexts["FINAL REVIEW"].waitForExistence(timeout: 5))
    }

    /// Opt-in integration test. A dedicated simulator must contain six qa365-*.jpg
    /// fixtures dated October 2026. Both the app and runner need Photos access.
    func testFixtureSwipesRestoreAndConfirmedDelete() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let end = try XCTUnwrap(cal.date(byAdding: .month, value: 1, to: start))
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        try XCTSkipUnless(assets.count == 6)
        var ids = [String]()
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            let name = PHAssetResource.assetResources(for: asset).first?.originalFilename
            try XCTSkipUnless(name == "qa365-\(5-i).jpg")
            ids.append(asset.localIdentifier)
        }

        let app = XCUIApplication()
        app.launch()
        let month = app.buttons["October, 0 of 6 reviewed"]
        XCTAssertTrue(month.waitForExistence(timeout: 12))
        capture("Home", app: app)
        month.tap()
        let card = app.buttons["photoCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        capture("Review", app: app)
        card.swipeLeft()
        expect("1 / 6", element: app.staticTexts["roundProgress"])
        app.buttons["undoSwipe"].tap()
        expect("0 / 6", element: app.staticTexts["roundProgress"])
        card.swipeRight()
        expect("1 / 6", element: app.staticTexts["roundProgress"])
        app.buttons["queuePhoto"].tap()
        app.buttons["queuePhoto"].tap()
        app.buttons["queuePhoto"].tap()
        app.terminate()
        app.launch()
        app.buttons["startRound"].tap()
        expect("4 / 6", element: app.staticTexts["roundProgress"])
        app.buttons["reviewBin"].tap()
        expect("0 of 3 selected", element: app.staticTexts["binCount"])
        capture("Review bin", app: app)
        app.buttons.matching(identifier: "previewBinPhoto").firstMatch.tap()
        app.buttons["Done"].tap()
        app.buttons.matching(identifier: "selectBinPhoto").firstMatch.tap()
        app.buttons["restoreSelected"].tap()
        expect("0 of 2 selected", element: app.staticTexts["binCount"])
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 6)
        app.buttons.matching(identifier: "selectBinPhoto").firstMatch.tap()
        app.buttons["deleteSelected"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = system.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Cancel|Don’t Allow|Не разрешать|Отменить|Отмена")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), system.debugDescription)
        cancel.tap()
        expect("1 of 2 selected", element: app.staticTexts["binCount"])
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 6)
        app.buttons["deleteSelected"].tap()
        let confirm = system.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Delete.*|Удалить.*")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        expect("0 of 1 selected", element: app.staticTexts["binCount"])
        app.buttons["Keep everything in Photos"].tap()
        XCTAssertTrue(app.staticTexts["emptyBin"].waitForExistence(timeout: 10))
        let remaining = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        XCTAssertEqual(remaining.count, 5)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [ids[2]], options: nil).count, 0)
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func expect(_ label: String, element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 6), .completed, file: file, line: line)
    }
}
