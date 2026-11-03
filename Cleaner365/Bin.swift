import SwiftUI
import Photos

struct BinScreen: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var preview: PreviewAsset?

    var body: some View {
        let queued = library.queued
        let ids = Set(queued.map(\.localIdentifier))
        let picked = selected.intersection(ids)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TimingLabel("FINAL REVIEW").foregroundStyle(Color.track)
                Text("Review bin").font(.largeTitle.bold())
                if queued.isEmpty {
                    Image(systemName: "tray").font(.system(size: 56, weight: .light)).foregroundStyle(Color.track).padding(.top, 30)
                    Text("Your bin is empty").font(.title.bold()).accessibilityIdentifier("emptyBin")
                    Text("Items queued from a round or a cleanup collection stay in Photos until you confirm deletion.")
                        .foregroundStyle(.secondary)
                    Button { dismiss() } label: { ActionLabel(title: "Done", icon: "checkmark") }.buttonStyle(.plain)
                } else {
                    Text("Select items to keep or delete. Tap a thumbnail for a closer look.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("\(picked.count) of \(queued.count) selected").font(.subheadline.monospacedDigit())
                            .accessibilityIdentifier("binCount")
                        Spacer()
                        Button(picked == ids ? "Deselect all" : "Select all") { selected = picked == ids ? [] : ids }
                    }.font(.subheadline)
                    if !picked.isEmpty {
                        SelectedVolume(assets: queued.filter { picked.contains($0.localIdentifier) })
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 134), spacing: 10)], spacing: 10) {
                        ForEach(queued, id: \.localIdentifier) { asset in
                            let id = asset.localIdentifier
                            let marked = picked.contains(id)
                            ZStack(alignment: .topTrailing) {
                                Button { preview = PreviewAsset(asset: asset) } label: {
                                    AssetImage(asset: asset).aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }.overlay(alignment: .bottomLeading) { if asset.mediaType == .video { Image(systemName: "play.fill").padding(8).foregroundStyle(.white).allowsHitTesting(false) } }.accessibilityLabel("Preview item").accessibilityIdentifier("previewBinPhoto")
                                Button {
                                    if marked { selected.remove(id) } else { selected.insert(id) }
                                } label: {
                                    Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24, weight: .bold)).foregroundStyle(marked ? Color.track : .white)
                                        .padding(4).background(.black.opacity(0.72), in: Circle()).padding(5)
                                        .frame(minWidth: 44, minHeight: 44)
                                }.accessibilityLabel(marked ? "Deselect item" : "Select item")
                                    .accessibilityIdentifier("selectBinPhoto")
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("Keep everything in Photos") { library.keep(ids); selected = [] }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }
            }.padding(18).frame(maxWidth: 580, alignment: .leading)
        }.frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            if !queued.isEmpty {
                VStack(spacing: 10) {
                    if library.deleting { ProgressView("Checking selection…").font(.caption) }
                    Text("With iCloud Photos, deletion syncs across your devices. You can usually recover items from Recently Deleted for 30 days.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Keep (\(picked.count))") { library.keep(picked); selected = [] }
                            .buttonStyle(.bordered).accessibilityIdentifier("restoreSelected")
                        Spacer()
                        Button("Delete (\(picked.count))", role: .destructive) {
                            Task { await library.delete(picked) }
                        }.buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("deleteSelected")
                    }.disabled(picked.isEmpty)
                }.padding().background(.bar)
            }
        }
        .disabled(library.deleting)
        .background(Color.asphalt).navigationBarTitleDisplayMode(.inline)
        .onChange(of: ids) { _, new in selected.formIntersection(new) }
        .sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }
}

private struct SelectedVolume: View {
    let assets: [PHAsset]
    @State private var size: String?

    var body: some View {
        Group {
            if let size { Text("Original size: " + size).font(.caption).foregroundStyle(.secondary) }
            else { Color.clear.frame(height: 0) }
        }
        .task(id: assets) {
            size = nil
            guard #available(iOS 27, *) else { return }
            let selected = assets
            let bytes = await Task.detached(priority: .utility) { () -> Int64? in
                var total: Int64 = 0
                for asset in selected {
                    let resources = PHAssetResource.assetResources(for: asset)
                    guard !resources.isEmpty else { return nil }
                    for resource in resources {
                        guard let bytes = resource.dataSize else { return nil }
                        total += Int64(bytes)
                    }
                }
                return total
            }.value
            if !Task.isCancelled, let bytes { size = bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US"))) }
        }
    }
}
