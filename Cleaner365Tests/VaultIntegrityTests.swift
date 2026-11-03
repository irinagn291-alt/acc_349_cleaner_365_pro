import XCTest
import CryptoKit
import Photos
@testable import Cleaner365

final class VaultIntegrityTests: XCTestCase {
    // Use a disposable encrypted directory and read a known simulator fixture.
    func testDamagedCopyFailsThePreDeletionCheck() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        var fixture: PHAsset?
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, stop in
            if PHAssetResource.assetResources(for: asset).contains(where: { $0.originalFilename == "qa365-0.jpg" }) {
                fixture = asset
                stop.pointee = true
            }
        }
        let asset = try XCTUnwrap(fixture)
        let files = VaultFiles(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try files.prepare()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let key = SymmetricKey(size: .bits256)
        let copy = try await files.archive(asset, key: key)
        try await files.verify(copy, against: asset, key: key)
        let resource = try XCTUnwrap(copy.resources.first)
        let path = files.folder(copy.id).appendingPathComponent(resource.id)
        var bytes = try Data(contentsOf: path)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: path)
        do {
            try await files.verify(copy, against: asset, key: key)
            XCTFail("A corrupted copy must not authorize source deletion.")
        } catch CryptoKitError.authenticationFailure {}
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil).count, 1)
    }
}
