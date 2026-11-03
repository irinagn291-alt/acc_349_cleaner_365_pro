import Foundation
import Photos
import SwiftUI
import WidgetKit

struct Month: Hashable, Comparable {
    let year: Int
    let number: Int

    init(year: Int, number: Int) { self.year = year; self.number = number }
    init(date: Date?, calendar: Calendar) {
        let parts = date.map { calendar.dateComponents([.year, .month], from: $0) }
        year = parts?.year ?? 0
        number = parts?.month ?? 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.number) < (rhs.year, rhs.number)
    }
    static let names = ["January", "February", "March", "April", "May", "June",
                        "July", "August", "September", "October", "November", "December"]
    var name: String { number == 0 ? "Undated" : Self.names[number - 1] }
    var key: String { "\(year)-\(number)" }
}

private struct Journal: Codable {
    var decisions: [String: Bool] = [:] // true = remains in Photos, false = in the review bin
    var rounds: [String: [String]] = [:]
    var lastMonth: String?
    var duplicateFamilies: [String: [String]]?
}

@MainActor
final class Library: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private var journal = Journal()
    @Published private(set) var groups: [Month: [PHAsset]] = [:]
    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var loading = false
    @Published private(set) var deleting = false
    @Published var message: String?
    private var byID: [String: PHAsset] = [:]
    private var reloadTask: Task<Void, Never>?
    @Published private(set) var screenshots: [PHAsset] = []
    @Published private(set) var recordings: [PHAsset] = []
    @Published private(set) var cleanup = CleanupResult()
    @Published private(set) var scanning = false
    private var cleanupTask: Task<Void, Never>?
    private var scanRequested = false
    private var scanned = false
    private var lastSummary = ReviewSummary.read()
    private var observing = false
    private let storageKey = "reviewJournal.v1"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(Journal.self, from: data) { journal = stored }
        _ = PhoneConnectivity.shared
        refresh()
    }
    deinit { if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }

    var hasAccess: Bool { status == .authorized || status == .limited }
    var months: [Month] { groups.keys.sorted(by: >) }
    var lastMonth: Month? { months.first { $0.key == journal.lastMonth } }
    var queued: [PHAsset] {
        journal.decisions.compactMap { $0.value ? nil : byID[$0.key] }
            .sorted { ($0.creationDate ?? .distantPast, $0.localIdentifier) > ($1.creationDate ?? .distantPast, $1.localIdentifier) }
    }

    func decision(_ id: String) -> Bool? { journal.decisions[id] }
    func asset(_ id: String) -> PHAsset? { byID[id] }
    func assets(in month: Month) -> [PHAsset] { groups[month] ?? [] }
    func reviewed(_ month: Month) -> Int {
        assets(in: month).reduce(0) { $0 + (decision($1.localIdentifier) == nil ? 0 : 1) }
    }
    func round(_ month: Month) -> [PHAsset] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return (journal.rounds[month.key] ?? []).compactMap { id in
            guard let asset = byID[id], Month(date: asset.creationDate, calendar: calendar) == month else { return nil }
            return asset
        }
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refresh()
    }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.refresh() }
    }
    func refresh() {
        reloadTask?.cancel()
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard hasAccess else {
            cleanupTask?.cancel()
            groups = [:]; byID = [:]; screenshots = []; recordings = []
            cleanup = CleanupResult(); scanning = false; scanned = false; loading = false
            publishSummary()
            return
        }
        if !observing { PHPhotoLibrary.shared().register(self); observing = true }
        loading = true
        reloadTask = Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                let result = PHAsset.fetchAssets(with: options)
                var groups: [Month: [PHAsset]] = [:]
                var index: [String: PHAsset] = [:]
                var shots: [PHAsset] = []
                var clips: [PHAsset] = []
                let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenRecordings, options: nil)
                var recorded = Set<String>()
                albums.enumerateObjects { album, _, _ in
                    PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in recorded.insert(asset.localIdentifier) }
                }
                result.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .image {
                        groups[Month(date: asset.creationDate, calendar: calendar), default: []].append(asset)
                        if asset.mediaSubtypes.contains(.photoScreenshot) { shots.append(asset) }
                    } else if recorded.contains(asset.localIdentifier) || asset.mediaSubtypes.contains(.videoScreenRecording) { clips.append(asset) }
                    index[asset.localIdentifier] = asset
                }
                return (groups, index, shots, clips)
            }.value
            guard !Task.isCancelled else { return }
            let changed = byID.count != snapshot.1.count || snapshot.1.contains { id, asset in
                guard let previous = byID[id] else { return true }
                return previous.modificationDate != asset.modificationDate || previous.isFavorite != asset.isFavorite
            }
            screenshots = snapshot.2; recordings = snapshot.3
            groups = snapshot.0
            byID = snapshot.1
            var revised = journal
            for (id, keep) in journal.decisions {
                if let asset = byID[id], !keep && asset.isFavorite { revised.decisions[id] = true }
                else if byID[id] == nil && status == .authorized { revised.decisions.removeValue(forKey: id) }
            }
            if revised.decisions != journal.decisions { journal = revised; persist() }
            loading = false
            publishSummary()
            if changed { scanned = false; cleanup = CleanupResult() }
            if scanRequested && (changed || (!scanned && !scanning)) { scan(cloud: false) }
        }
    }
    func begin(_ month: Month, whole: Bool = false, newRound: Bool = false) {
        let pending = assets(in: month).filter { decision($0.localIdentifier) == nil }
        let existing = round(month)
        if newRound || !existing.contains(where: { decision($0.localIdentifier) == nil }) {
            if !pending.isEmpty || existing.isEmpty {
                journal.rounds[month.key] = pending.prefix(whole ? pending.count : 20).map(\.localIdentifier)
            }
        }
        journal.lastMonth = month.key
        persist()
    }
    func decide(_ asset: PHAsset, keep: Bool) -> Bool {
        let id = asset.localIdentifier
        guard !deleting, let current = byID[id], decision(id) == nil else { return false }
        if !keep && (current.isFavorite || !current.canPerform(.delete)) {
            message = "This photo is protected. You can keep it in Photos."
            return false
        }
        if !keep && !queue([id]).contains(id) {
            message = "Keep at least one copy of this file in Photos."
            return false
        }
        if !keep { return true }
        journal.decisions[id] = keep
        persist()
        return true
    }
    func undo(_ id: String, expected: Bool) {
        guard !deleting, byID[id] != nil, decision(id) == expected else { return }
        journal.decisions.removeValue(forKey: id)
        persist()
    }
    func keep(_ ids: Set<String>) {
        guard !deleting else { return }
        for id in ids where decision(id) == false { journal.decisions[id] = true }
        persist()
    }
    func delete(_ ids: Set<String>) async {
        guard !deleting, !ids.isEmpty, ids.allSatisfy({ decision($0) == false }) else { return }
        deleting = true
        defer { deleting = false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var allowed = assets.count == ids.count
        assets.enumerateObjects { asset, _, _ in
            if asset.isFavorite || !asset.canPerform(.delete) { allowed = false }
        }
        guard allowed else {
            message = "Access or selection changed. Check the updated bin before trying again."
            refresh()
            return
        }
        do {
            let proof = try await CleanupScanner.deletionCheck(ids, known: journal.duplicateFamilies ?? [:])
            remember(proof.groups)
            if protectSurvivors(in: proof.groups, among: ids) {
                persist()
                message = "One copy of each duplicate set has been kept. Review the remaining selection."
                return
            }
            var checked = proof.witnesses
            assets.enumerateObjects { a, _, _ in checked.append(a) }
            let current = PHAsset.fetchAssets(withLocalIdentifiers: checked.map(\.localIdentifier), options: nil)
            let versions = Dictionary(uniqueKeysWithValues: checked.map { ($0.localIdentifier, $0) })
            var unchanged = current.count == checked.count
            current.enumerateObjects { a, _, _ in
                if versions[a.localIdentifier]?.modificationDate != a.modificationDate ||
                    (ids.contains(a.localIdentifier) && (a.isFavorite || !a.canPerform(.delete))) { unchanged = false }
            }
            guard unchanged else { throw ScanError.changed }
            persist()
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
            for id in ids { journal.decisions.removeValue(forKey: id); byID.removeValue(forKey: id) }
            let remaining = proof.groups.mapValues { $0.filter { !ids.contains($0) } }
            _ = protectSurvivors(in: remaining, among: Set(queued.map(\.localIdentifier)))
            scanned = false
            groups = groups.compactMapValues { assets in
                let stillPresent = assets.filter { !ids.contains($0.localIdentifier) }
                return stillPresent.isEmpty ? nil : stillPresent
            }
            persist()
            refresh()
        } catch {
            let failure = error as NSError
            if !(failure.domain == PHPhotosErrorDomain && failure.code == PHPhotosError.Code.userCancelled.rawValue) {
                message = (error as? ScanError)?.errorDescription ?? "Could not delete the selection. Check Photos access and try again."
            }
        }
    }
    func requestScan() {
        scanRequested = true
        if hasAccess && !loading && !scanned && !scanning { scan(cloud: false) }
    }
    func scan(cloud: Bool) {
        guard hasAccess else { return }
        scanRequested = true
        cleanupTask?.cancel()
        scanning = true
        let assets = Array(byID.values)
        let previous = Set((journal.duplicateFamilies ?? [:]).values.joined())
        cleanupTask = Task {
            do {
                let result = try await CleanupScanner.scan(assets, cloud: cloud, previouslyMatched: previous)
                try Task.checkCancellation()
                cleanup = result
                if let known = journal.duplicateFamilies {
                    journal.duplicateFamilies = known.reduce(into: [:]) { revised, entry in
                        let current = entry.value.filter { id in
                            if let signature = result.signatures[id] { return signature == entry.key }
                            return byID[id] != nil || status == .limited
                        }
                        if !current.isEmpty { revised[entry.key] = current }
                    }
                }
                remember(result.duplicates)
                _ = protectSurvivors(in: result.duplicates, among: Set(queued.map(\.localIdentifier)))
                persist()
                scanned = true
                scanning = false
            } catch { if !Task.isCancelled { scanning = false; message = "Could not finish this scan. Please try again." } }
        }
    }
    private func remember(_ families: [String: [String]]) {
        guard !families.isEmpty else { return }
        var known = journal.duplicateFamilies ?? [:]
        for (key, members) in families {
            known[key] = Array(Set(known[key] ?? []).union(members)).sorted()
        }
        journal.duplicateFamilies = known
    }
    func preferred(_ ids: [String]) -> [PHAsset] {
        ids.compactMap { byID[$0] }.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            if (decision(a.localIdentifier) == true) != (decision(b.localIdentifier) == true) { return decision(a.localIdentifier) == true }
            return (a.creationDate ?? .distantFuture, a.localIdentifier) < (b.creationDate ?? .distantFuture, b.localIdentifier)
        }
    }
    // Families passed by the deletion verifier contain only freshly matched, accessible assets.
    private func protectSurvivors(in families: [String: [String]], among ids: Set<String>) -> Bool {
        var retained = false
        for members in families.values where !members.isEmpty && members.allSatisfy(ids.contains) {
            if let keeper = preferred(members).first?.localIdentifier ?? members.first {
                journal.decisions[keeper] = true
                retained = true
            }
        }
        return retained
    }
    func allowedSelection(_ proposed: Set<String>) -> Set<String> {
        var allowed = Set(proposed.filter { id in
            guard let a = byID[id] else { return false }
            return decision(id) != false && !a.isFavorite && a.canPerform(.delete)
        })
        for members in (journal.duplicateFamilies ?? [:]).values {
            let ordered = preferred(members)
            if !ordered.isEmpty && ordered.allSatisfy({ decision($0.localIdentifier) == false || allowed.contains($0.localIdentifier) }),
               let keeper = ordered.first(where: { allowed.contains($0.localIdentifier) }) { allowed.remove(keeper.localIdentifier) }
        }
        return allowed
    }
    @discardableResult func queue(_ ids: Set<String>) -> Set<String> {
        guard !deleting else { return [] }
        let allowed = allowedSelection(ids)
        for id in allowed { journal.decisions[id] = false }
        if !allowed.isEmpty { persist() }
        return allowed
    }
    private func publishSummary() {
        let total = groups.values.reduce(0) { $0 + $1.count }
        let reviewed = journal.decisions.keys.reduce(0) { $0 + (byID[$1]?.mediaType == .image ? 1 : 0) }
        let count = queued.count
        guard lastSummary.updated == nil || lastSummary.total != total || lastSummary.reviewed != reviewed || lastSummary.queued != count else { return }
        lastSummary = ReviewSummary(reviewed: reviewed, total: total, queued: count, updated: Date())
        lastSummary.write()
        WidgetCenter.shared.reloadTimelines(ofKind: "Cleaner365Widget")
        PhoneConnectivity.shared.publish(lastSummary)
    }
    private func persist() {
        publishSummary()
        if let data = try? JSONEncoder().encode(journal) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}
