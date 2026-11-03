import SwiftUI
import Photos

enum CollectionKind: String, CaseIterable, Hashable {
    case duplicates = "Exact duplicates"
    case screenshots = "Screenshots"
    case recordings = "Screen recordings"
    case videos = "Large videos"

    var icon: String {
        switch self {
        case .duplicates: "square.on.square"
        case .screenshots: "viewfinder"
        case .recordings: "record.circle"
        case .videos: "film.stack"
        }
    }
    var caption: String {
        switch self {
        case .duplicates: "Identical files, including Live Photo motion"
        case .screenshots: "Captures from your photo library"
        case .recordings: "Videos recorded from your screen"
        case .videos: "100 MB or larger · biggest first"
        }
    }
    var indexed: Bool { self == .duplicates || self == .videos }
}

struct CleanupScreen: View {
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openBin: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    TimingLabel("365 / FIELD GUIDE").foregroundStyle(Color.track)
                    Text("Cleanup").font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("Four collections. One review bin.").font(.subheadline.weight(.medium))
                    Text("Nothing leaves Photos until you confirm.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .trailing) {
                        TrackMark().frame(width: 100).opacity(0.35).clipped().accessibilityHidden(true)
                    }
                    .background(Color.lane, in: RoundedRectangle(cornerRadius: 20)).clipShape(RoundedRectangle(cornerRadius: 20))
                if !library.hasAccess {
                    Button {
                        if library.status == .notDetermined { Task { await library.requestAccess() } }
                        else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: { ActionLabel(title: library.status == .notDetermined ? "Choose photos" : "Open Settings") }
                } else {
                    if library.status == .limited { Label("Showing the items you shared with Cleaner 365.", systemImage: "eye").font(.caption) }
                    TimingLabel("LIBRARY / COLLECTIONS").foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(CollectionKind.allCases, id: \.self) { kind in
                            NavigationLink(value: Route.collection(kind)) {
                                HStack(spacing: 14) {
                                    Image(systemName: kind.icon).foregroundStyle(Color.track).font(.title2).frame(width: 42, height: 42)
                                        .background(Color.track.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(kind.rawValue).font(.headline)
                                        Text(kind.caption).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(count(kind)).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                                        .contentTransition(.numericText())
                                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: count(kind))
                                    Image(systemName: "chevron.right").font(.caption2)
                                }.padding(12).background(Color.lane, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityIdentifier("collection-" + kind.rawValue)
                        }
                    }
                    if library.scanning { ProgressView("Checking originals…").font(.caption) }
                    else if !library.cleanup.unavailable.isEmpty {
                        Text("\(library.cleanup.unavailable.count) items could not be fully checked. Retry with iCloud originals if they are not on this iPhone.").font(.caption).foregroundStyle(.secondary)
                        Button("Scan with iCloud downloads") { library.scan(cloud: true) }
                    }
                    Button(action: openBin) { ActionLabel(title: "Review bin (\(library.queued.count))", icon: "tray") }
                        .buttonStyle(.plain).accessibilityIdentifier("cleanupBin")
                }
            }.padding(20).frame(maxWidth: 590)
        }.frame(maxWidth: .infinity).background(Color.asphalt).navigationBarTitleDisplayMode(.inline)
        .onAppear { library.requestScan() }
    }
    private func count(_ kind: CollectionKind) -> String {
        if kind.indexed && library.scanning { return "…" }
        switch kind {
        case .duplicates: return String(library.cleanup.duplicates.count)
        case .screenshots: return String(library.screenshots.count)
        case .recordings: return String(library.recordings.count)
        case .videos: return String(library.cleanup.largeVideos.count)
        }
    }
}

struct CollectionScreen: View {
    let kind: CollectionKind
    let openBin: () -> Void
    @EnvironmentObject private var library: Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Set<String> = []
    @State private var preview: PreviewAsset?
    @State private var feedback = ""
    private var sets: [[PHAsset]] {
        switch kind {
        case .duplicates:
            return library.cleanup.duplicates.sorted { $0.key < $1.key }
                .map { library.preferred($0.value) }.filter { $0.count > 1 }
        case .screenshots: return [library.screenshots]
        case .recordings: return [library.recordings]
        case .videos: return [library.cleanup.largeVideos.compactMap { library.asset($0.id) }]
        }
    }
    var body: some View {
        let sections = sets
        let all = Set(sections.flatMap { $0.map(\.localIdentifier) })
        let picked = selected.intersection(all)
        let sizes = Dictionary(uniqueKeysWithValues: library.cleanup.largeVideos.map { ($0.id, $0.bytes) })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                TimingLabel("CLEANUP / COLLECTION").foregroundStyle(Color.track)
                Text(kind.rawValue).font(.largeTitle.bold())
                Text(kind.caption).font(.subheadline).foregroundStyle(.secondary)
                if kind == .duplicates { Text("Keep at least one copy in every set. Favorites stay in Photos.").font(.caption) }
                if all.isEmpty {
                    if library.scanning && kind.indexed { ProgressView("Checking originals…").padding(.vertical) }
                    else {
                        Label("No \(kind.rawValue.lowercased()) found", systemImage: "checkmark.circle")
                            .font(.headline).padding(.vertical, 22)
                        if kind.indexed && !library.cleanup.unavailable.isEmpty { Text("Some originals could not be checked.").font(.caption) }
                    }
                } else {
                    Button(picked.isEmpty ? (kind == .duplicates ? "Select extra copies" : "Select all available") : "Deselect all") {
                        change { feedback = ""; selected = picked.isEmpty ? library.allowedSelection(all) : [] }
                    }.font(.subheadline.bold()).padding(.vertical, 6)
                    ForEach(sections.indices, id: \.self) { index in
                        let group = sections[index]
                        if kind == .duplicates {
                            TimingLabel("SET \(index + 1)  /  \(group.count) COPIES").padding(.top, 12)
                        }
                        ForEach(group, id: \.localIdentifier) { item in
                            let id = item.localIdentifier
                            let inBin = library.decision(id) == false
                            let marked = picked.contains(id)
                            HStack {
                                Button { preview = PreviewAsset(asset: item) } label: {
                                    AssetImage(asset: item, pixels: 260).frame(width: 76, height: 66).clipShape(RoundedRectangle(cornerRadius: 9))
                                }.accessibilityLabel("Preview item")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.creationDate?.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US"))) ?? "Undated").font(.subheadline.bold())
                                    if item.mediaType == .video {
                                        Text(Self.duration(item.duration) + (sizes[id].map { " · " + $0.formatted(.byteCount(style: .decimal).locale(Locale(identifier: "en_US"))) } ?? "")).font(.caption.monospacedDigit())
                                    } else { Text(item.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "\(item.pixelWidth) × \(item.pixelHeight)").font(.caption) }
                                    if inBin || item.isFavorite { Text(inBin ? "In review bin" : "Favorite · protected").font(.caption2).foregroundStyle(Color.track) }
                                }
                                Spacer()
                                Button {
                                    if marked { change { selected.remove(id); feedback = "" }; return }
                                    let next = picked.union([id])
                                    if library.allowedSelection(next) == next {
                                        change { selected = next; feedback = "" }
                                    } else { feedback = "One matching copy must stay in Photos." }
                                } label: {
                                    Image(systemName: inBin ? "tray.fill" : marked ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).frame(width: 44, height: 48)
                                }.accessibilityLabel(marked ? "Deselect item" : "Select item")
                                    .accessibilityIdentifier("select-" + id).disabled(inBin || item.isFavorite || !item.canPerform(.delete))
                            }
                            Divider()
                        }
                    }
                }
            }.padding(20)
        }.background(Color.asphalt).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !feedback.isEmpty { Text(feedback).font(.caption).accessibilityIdentifier("queueFeedback") }
                HStack {
                    Button { openBin() } label: { Image(systemName: "tray").frame(width: 45, height: 45) }
                        .accessibilityLabel("Review bin").accessibilityIdentifier("collectionBin")
                    Button {
                        let added = library.queue(picked)
                        change { selected = []; feedback = "\(added.count) added to your review bin." }
                    } label: { ActionLabel(title: "Queue selection (\(picked.count))", icon: "plus") }
                        .buttonStyle(.plain).disabled(picked.isEmpty).opacity(picked.isEmpty ? 0.5 : 1).accessibilityIdentifier("queueCollection")
                }
            }.padding(.horizontal, 18).padding(.vertical, 8).background(.bar)
        }.sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }
    private func change(_ action: () -> Void) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18), action) }
    private static func duration(_ value: TimeInterval) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
