import XCTest
import Photos
import CryptoKit
import LocalAuthentication

final class VaultTests: XCTestCase {
    private let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }

    // Runs only on the disposable QA simulator. Both records belong to this test run.
    @MainActor func testVaultRoundTrip() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let leftover = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Don’t Allow|Cancel|Отмена|Не разрешать")).firstMatch
        if leftover.exists { leftover.tap() }
        let bundle = Bundle(for: Self.self)
        let image = try XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "jpg"))
        let video = try XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "mov"))
        let prefix = UUID().uuidString
        let date = Date(timeIntervalSince1970: 2_410_000_000)
        var ids: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for live in [false, true] {
                let req = PHAssetCreationRequest.forAsset()
                req.creationDate = date.addingTimeInterval(live ? 1 : 0)
                let name = PHAssetResourceCreationOptions()
                name.originalFilename = prefix + (live ? "-live.jpg" : "-photo.jpg")
                req.addResource(with: .photo, fileURL: image, options: name)
                if live {
                    let paired = PHAssetResourceCreationOptions()
                    paired.originalFilename = prefix + ".mov"
                    req.addResource(with: .pairedVideo, fileURL: video, options: paired)
                }
                ids.append(req.placeholderForCreatedAsset!.localIdentifier)
            }
        }
        let original = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [ids[1]], options: nil).firstObject)
        XCTAssertTrue(original.mediaSubtypes.contains(.photoLive))
        let expectedMotion = try await fingerprints(original)
        let expectedPhoto = try await fingerprints(XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [ids[0]], options: nil).firstObject))

        app = XCUIApplication()
        app.launch()
        app.buttons["openVault"].tap()
        XCTAssertTrue(app.buttons["unlockVault"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["addToVault"].exists)
        try unlock()
        app.buttons["addToVault"].tap()
        for id in ids {
            let choice = app.buttons["pick-" + id]
            XCTAssertTrue(choice.waitForExistence(timeout: 10))
            choice.tap()
        }
        app.buttons["importVaultSelection"].tap()
        XCTAssertTrue(app.buttons["deleteVaultOriginals"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 2)
        app.buttons["deleteVaultOriginals"].tap()
        let confirm = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Delete.*|Удалить.*")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), system.debugDescription)
        let cancel = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Don’t Allow|Cancel|Не разрешать|Отмена")).firstMatch
        cancel.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 2)
        app.buttons["deleteVaultOriginals"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        if !confirm.waitForNonExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), app.debugDescription + system.debugDescription)
        app.buttons["Done"].tap()
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 0)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["unlockVault"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        app.buttons["openVault"].tap()
        try unlock()
        for (type, live) in [("vaultLiveTile", true), ("vaultPhotoTile", false)] {
            // New copies appear first in the vault.
            app.buttons.matching(identifier: type).firstMatch.tap()
            if live {
                app.buttons["playVaultMotion"].tap()
                XCTAssertTrue(app.descendants(matching: .any)["vaultMotionPlayer"].waitForExistence(timeout: 8))
            }
            app.buttons["exportVaultPhoto"].tap()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.staticTexts["Saved to Photos. Your vault copy stays here."].exists)
            done.tap()
            let fetch = PHFetchOptions()
            fetch.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", date as NSDate, date.addingTimeInterval(2) as NSDate)
            let result = PHAsset.fetchAssets(with: .image, options: fetch)
            var restored: PHAsset?
            result.enumerateObjects { asset, _, _ in
                if PHAssetResource.assetResources(for: asset).contains(where: {
                    $0.originalFilename == prefix + (live ? "-live.jpg" : "-photo.jpg")
                }) { restored = asset }
            }
            let asset = try XCTUnwrap(restored)
            let actual = try await fingerprints(asset)
            XCTAssertEqual(actual, live ? expectedMotion : expectedPhoto)
            if live {
                XCTAssertTrue(asset.mediaSubtypes.contains(.photoLive))
                let motion: PHLivePhoto? = await withCheckedContinuation { c in
                    let opts = PHLivePhotoRequestOptions()
                    opts.deliveryMode = .highQualityFormat
                    PHImageManager.default().requestLivePhoto(for: asset, targetSize: CGSize(width: 160, height: 160),
                        contentMode: .aspectFit, options: opts) { photo, info in
                        if info?[PHLivePhotoInfoIsDegradedKey] as? Bool != true { c.resume(returning: photo) }
                    }
                }
                XCTAssertNotNil(motion)
            }
            app.buttons["All photos"].tap()
            XCTAssertTrue(app.buttons.matching(identifier: type).firstMatch.exists)
        }
    }

    @MainActor private func unlock() throws {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 0.8, repeating: 0.4)
        timer.setEventHandler { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("com.apple.BiometricKit_Sim.pearl.match" as CFString), nil, nil, true) }
        timer.resume()
        defer { timer.cancel() }
        app.buttons["unlockVault"].tap()
        let allow = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Allow|OK|Разрешить|ОК")).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let localAllow = app.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Allow|OK|Разрешить|ОК")).firstMatch
        if localAllow.exists { localAllow.tap() }
        XCTAssertTrue(app.buttons["addToVault"].waitForExistence(timeout: 8), app.debugDescription + system.debugDescription)
    }

    private func fingerprints(_ asset: PHAsset) async throws -> [String] {
        var result: [String] = []
        for resource in PHAssetResource.assetResources(for: asset) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: nil)
            let hash = SHA256.hash(data: try Data(contentsOf: url))
            result.append("\(resource.type.rawValue)-\(Data(hash).base64EncodedString())")
        }
        return result.sorted()
    }
}
