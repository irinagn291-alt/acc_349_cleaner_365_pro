import CryptoKit
import Foundation
import Photos

struct CleanupResult {
    var duplicates: [String: [String]] = [:]
    var signatures: [String: String] = [:]
    var largeVideos: [(id: String, bytes: Int64)] = []
    var unavailable = Set<String>()
}

enum CleanupScanner {
    static let largeVideoBytes: Int64 = 100_000_000

    struct Bucket: Hashable {
        let type, width, height: Int
        init(_ asset: PHAsset) {
            type = asset.mediaType.rawValue
            width = asset.pixelWidth
            height = asset.pixelHeight
        }
    }

    // Most library items need no content comparison. Geometry only narrows the candidates.
    static func scan(_ assets: [PHAsset], cloud: Bool, previouslyMatched: Set<String> = []) async throws -> CleanupResult {
        let buckets = Dictionary(grouping: assets, by: Bucket.init)
        var matches: [String: [String]] = [:]
        var result = CleanupResult()
        for group in buckets.values {
            for asset in group {
                try Task.checkCancellation()
                let compare = group.count > 1 || previouslyMatched.contains(asset.localIdentifier)
                guard compare || asset.mediaType == .video else { continue }
                do {
                    let info = try await inspect(asset, hash: compare, cloud: cloud)
                    if let signature = info.signature {
                        matches[signature, default: []].append(asset.localIdentifier)
                        result.signatures[asset.localIdentifier] = signature
                    }
                    if asset.mediaType == .video && info.bytes >= largeVideoBytes {
                        result.largeVideos.append((asset.localIdentifier, info.bytes))
                    }
                } catch {
                    try Task.checkCancellation()
                    #if compiler(>=6.4)
                    if compare, asset.mediaType == .video, #available(iOS 27, *) {
                        let resources = PHAssetResource.assetResources(for: asset)
                        let sizes = resources.compactMap(\.dataSize)
                        if sizes.count == resources.count {
                            let bytes = sizes.reduce(Int64(0)) { $0 + Int64($1) }
                            if bytes >= largeVideoBytes { result.largeVideos.append((asset.localIdentifier, bytes)) }
                        }
                    }
                    #endif
                    result.unavailable.insert(asset.localIdentifier)
                }
            }
        }
        result.duplicates = matches.filter { $0.value.count > 1 }
        result.largeVideos.sort { ($0.bytes, $0.id) > ($1.bytes, $1.id) }
        return result
    }

    static func inspect(_ asset: PHAsset, hash: Bool, cloud: Bool) async throws -> (signature: String?, bytes: Int64) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw ScanError.unavailable }
        var parts: [String] = []
        var size: Int64 = 0
        for resource in resources {
            try Task.checkCancellation()
            // dataSize is declared starting with the iOS 27 SDK (Xcode 27).
            #if compiler(>=6.4)
            if !hash, #available(iOS 27, *), let bytes = resource.dataSize {
                size += Int64(bytes)
                continue
            }
            #endif
            let stream = ContentRead()
            let result = try await stream.read(resource, hash: hash, cloud: cloud)
            guard result.bytes > 0 else { throw ScanError.unavailable }
            size += result.bytes
            if hash { parts.append("\(resource.type.rawValue):" + result.digest) }
        }
        return (hash ? "\(asset.mediaType.rawValue)/" + parts.sorted().joined(separator: "/") : nil, size)
    }

    // Verify the selected files even if cleanup hasn't been opened in this session.
    // A lone, previously identified survivor remains protected across launches.
    static func deletionCheck(_ selected: Set<String>, known: [String: [String]]) async throws -> (groups: [String: [String]], witnesses: [PHAsset]) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(selected), options: nil)
        var picked: [PHAsset] = []
        fetched.enumerateObjects { a, _, _ in picked.append(a) }
        guard picked.count == selected.count else { throw ScanError.changed }
        let selectedBuckets = Dictionary(grouping: picked, by: Bucket.init)
        let knownIDs = Set(known.values.joined())
        let all = PHAsset.fetchAssets(with: nil)
        var candidates: [Bucket: [PHAsset]] = [:]
        all.enumerateObjects { a, _, _ in
            let bucket = Bucket(a)
            if selectedBuckets[bucket] != nil { candidates[bucket, default: []].append(a) }
        }
        var groups: [String: [String]] = [:]
        var witnesses: [PHAsset] = []
        for (bucket, chosen) in selectedBuckets {
            let others = (candidates[bucket] ?? []).filter { !selected.contains($0.localIdentifier) }
            if others.isEmpty && chosen.count == 1 && !knownIDs.contains(chosen[0].localIdentifier) { continue }
            var pickedBySignature: [String: [String]] = [:]
            for asset in chosen {
                try Task.checkCancellation()
                guard let signature = try? await inspect(asset, hash: true, cloud: false).signature else { throw ScanError.unavailable }
                pickedBySignature[signature, default: []].append(asset.localIdentifier)
            }
            // A single unselected, byte-verified witness per signature suffices.
            var missing = Set(pickedBySignature.keys)
            let preferredIDs = Set(missing.flatMap { known[$0] ?? [] })
            let ordered = others.filter { preferredIDs.contains($0.localIdentifier) } + others.filter { !preferredIDs.contains($0.localIdentifier) }
            for candidate in ordered {
                if missing.isEmpty { break }
                try Task.checkCancellation()
                if let signature = try? await inspect(candidate, hash: true, cloud: false).signature,
                   missing.remove(signature) != nil {
                    pickedBySignature[signature, default: []].append(candidate.localIdentifier)
                    witnesses.append(candidate)
                }
            }
            for (signature, ids) in pickedBySignature where ids.count > 1 || known[signature] != nil {
                groups[signature] = ids
            }
        }
        return (groups, witnesses)
    }
}

enum ScanError: LocalizedError {
    case unavailable, changed
    var errorDescription: String? {
        switch self {
        case .unavailable: return "An original could not be verified. Download it in Photos, then try again."
        case .changed: return "Your library changed. Check your selection and try again."
        }
    }
}

private final class ContentRead: @unchecked Sendable {
    private let lock = NSLock()
    private var request: PHAssetResourceDataRequestID?
    private var cancelled = false

    func read(_ resource: PHAssetResource, hash: Bool, cloud: Bool) async throws -> (digest: String, bytes: Int64) {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { c in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = cloud
                var hasher = SHA256()
                var bytes: Int64 = 0
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    bytes += Int64(data.count)
                    if hash { hasher.update(data: data) }
                } completionHandler: { error in
                    if let error { c.resume(throwing: error) }
                    else { c.resume(returning: (hash ? Data(hasher.finalize()).base64EncodedString() : "", bytes)) }
                }
                lock.lock()
                request = id
                let cancelNow = cancelled
                lock.unlock()
                if cancelNow { PHAssetResourceManager.default().cancelDataRequest(id) }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let id = self.request
            self.lock.unlock()
            if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
    }
}
