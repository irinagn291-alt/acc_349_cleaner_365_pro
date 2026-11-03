import Photos
import UIKit
import UserNotifications
import XCTest
@testable import Cleaner365

final class CleanupTests: XCTestCase {
    func testMonthlyReminderIsPassiveAndRepeatsOnlyOncePerMonth() throws {
        let request = ReminderSettings.request()
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.day, 1)
        XCTAssertEqual(trigger.dateComponents.hour, 19)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertNil(trigger.dateComponents.timeZone)
        XCTAssertEqual(request.content.interruptionLevel, .passive)
        XCTAssertNil(request.content.sound)
        XCTAssertNil(request.content.badge)
        XCTAssertEqual(request.identifier, ReminderSettings.request().identifier)
    }

    private func requireQA() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Cleaner 365 QA")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
    }

    @MainActor
    func testExactBytesAndLastCopyAcrossBinSwipeAndRelaunch() async throws {
        try requireQA()
        let unique = UUID().uuidString
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 381, height: 243), format: format)
        func artwork(_ title: String) -> Data {
            renderer.jpegData(withCompressionQuality: 0.92) { ctx in
                UIColor(red: 0.08, green: 0.16, blue: 0.18, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 381, height: 243))
                UIColor(red: 0.77, green: 0.98, blue: 0.22, alpha: 1).setStroke()
                for i in 0..<8 {
                    let y = CGFloat(i * 11)
                    let lane = UIBezierPath(roundedRect: CGRect(x: 80 + y, y: -95 + y, width: 400 - 2*y, height: 270 - 2*y), cornerRadius: 120 - y)
                    lane.lineWidth = 2
                    lane.stroke()
                }
                (title as NSString).draw(at: CGPoint(x: 16, y: 133), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 43), .foregroundColor: UIColor.white])
                (unique as NSString).draw(at: CGPoint(x: 18, y: 207), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.white])
            }
        }
        let first = artwork("TRACK / 365")
        let variant = artwork("TRACK / 366")
        var ids: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for (i, bytes) in [first, first, variant].enumerated() {
                let create = PHAssetCreationRequest.forAsset()
                let option = PHAssetResourceCreationOptions()
                option.originalFilename = "cleanup-fixture-\(unique)-\(i).jpg"
                create.addResource(with: .photo, data: bytes, options: option)
                ids.append(create.placeholderForCreatedAsset!.localIdentifier)
            }
        }
        let pair = Set(ids.prefix(2))
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let result = try await CleanupScanner.scan(assets.objects(at: IndexSet(integersIn: 0..<assets.count)), cloud: false)
        XCTAssertEqual(result.duplicates.values.map(Set.init), [pair])
        XCTAssertTrue(result.unavailable.isEmpty)
        let one = try XCTUnwrap(pair.first)
        let proof = try await CleanupScanner.deletionCheck([one], known: result.duplicates)
        XCTAssertEqual(Set(proof.witnesses.map(\.localIdentifier)), pair.subtracting([one]))
        let library = Library()
        for _ in 0..<300 where library.loading { try await Task.sleep(for: .milliseconds(20)) }
        // Before a cleanup scan, independent monthly swipes could have queued both.
        XCTAssertEqual(library.queue(pair), pair)
        await library.delete(pair)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: Array(pair), options: nil).count, 2)
        let queued = pair.filter { library.decision($0) == false }
        XCTAssertEqual(queued.count, 1)
        let survivor = try XCTUnwrap(pair.subtracting(queued).first)
        XCTAssertEqual(library.decision(survivor), true)
        XCTAssertTrue(library.queue([survivor]).isEmpty)
        library.undo(survivor, expected: true)
        XCTAssertFalse(library.decide(try XCTUnwrap(library.asset(survivor)), keep: false))
        let restarted = Library()
        for _ in 0..<300 where restarted.loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(restarted.allowedSelection([survivor]).isEmpty)
        XCTAssertEqual(ReviewSummary.read().queued, restarted.queued.count)
        XCTAssertEqual(restarted.queue([ids[2]]), [ids[2]])
        restarted.keep(pair.union([ids[2]]))
    }

    @MainActor
    func testLargeVideoUsesOriginalFileSizeAndSharesBin() async throws {
        try requireQA()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VaultMotion", withExtension: "mov"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: source, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // A legal empty QuickTime atom pads the fixture across the 100 MB boundary.
        let handle = try FileHandle(forWritingTo: url)
        let start = try handle.seekToEnd()
        let bytes = UInt32(CleanupScanner.largeVideoBytes)
        var length = bytes.bigEndian
        try handle.write(contentsOf: Data(bytes: &length, count: 4) + Data("free".utf8))
        try handle.truncate(atOffset: start + UInt64(bytes))
        try handle.close()
        var ids: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for original in [source, url] {
                let create = PHAssetCreationRequest.forAsset()
                create.addResource(with: .video, fileURL: original, options: nil)
                ids.append(create.placeholderForCreatedAsset!.localIdentifier)
            }
        }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let result = try await CleanupScanner.scan(fetched.objects(at: IndexSet(integersIn: 0..<fetched.count)), cloud: false)
        XCTAssertEqual(result.largeVideos.map(\.id), [ids[1]])
        XCTAssertEqual(result.largeVideos.first?.bytes, Int64(start) + Int64(bytes))
        XCTAssertTrue(result.duplicates.isEmpty)
        let library = Library()
        for _ in 0..<300 where library.loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(library.groups.values.joined().contains(where: { $0.localIdentifier == ids[1] }))
        XCTAssertEqual(library.queue([ids[1]]), [ids[1]])
        XCTAssertTrue(library.queued.contains { $0.localIdentifier == ids[1] })
        library.keep([ids[1]])
    }
}
