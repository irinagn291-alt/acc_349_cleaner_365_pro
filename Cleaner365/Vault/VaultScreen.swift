import SwiftUI
import PhotosUI

struct VaultScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    @State private var picker = false
    @State private var detail: VaultPhoto?
    @State private var anchor = UIViewController()
    private let storageNote = "This vault lives on this iPhone. Before changing devices, removing the app, or changing Face ID, restore the photos you want to keep."
    private let deletionNote = "With iCloud Photos, removal syncs across your devices. Originals stay in Recently Deleted for up to 30 days."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    TimingLabel("365 / PRIVATE COLLECTION").foregroundStyle(Color.track)
                    Spacer()
                    if vault.unlocked {
                        Button { vault.lock() } label: { Image(systemName: "lock.fill").padding(8) }
                            .accessibilityLabel("Lock vault").accessibilityIdentifier("lockVault")
                    }
                }
                if !vault.unlocked { locked }
                else if let photo = detail { detailView(photo) }
                else { collection }
            }.padding(20).frame(maxWidth: 580, alignment: .leading)
        }
        .frame(maxWidth: .infinity).background(Color.asphalt)
        .navigationTitle("Vault").navigationBarTitleDisplayMode(.inline)
        .background(PickerAnchor(controller: anchor).frame(width: 0, height: 0))
        .onDisappear { vault.lock() }
        .onChange(of: vault.unlocked) { _, open in if !open { picker = false; detail = nil } }
        .sheet(isPresented: $picker) { VaultPicker { assets in
            picker = false
            Task { await vault.importPhotos(assets) }
        } }
        .alert("Vault", isPresented: Binding(get: { vault.notice != nil }, set: { if !$0 { vault.notice = nil } })) {
            Button("Done") { vault.notice = nil }
        } message: { Text(vault.notice ?? "") }
    }
    private var locked: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .leading) {
                TrackMark().opacity(0.55)
                Image(systemName: "lock.rectangle.on.rectangle").font(.system(size: 55, weight: .light))
                    .foregroundStyle(Color.track).padding(.leading, 20)
            }.frame(height: 130).background(Color.lane, in: RoundedRectangle(cornerRadius: 16)).clipped()
            Text("Private vault").font(.largeTitle.bold())
            Text("Open your photos and Live Photos with Face ID.").font(.headline)
            Text(storageNote).font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await vault.unlock() } } label: { ActionLabel(title: "Unlock with Face ID", icon: "faceid") }
                .buttonStyle(.plain).disabled(vault.busy).accessibilityIdentifier("unlockVault")
        }
    }
    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My collection").font(.largeTitle.bold())
            Button {
                Task {
                    if library.status == .notDetermined { await library.requestAccess() }
                    if library.hasAccess { picker = true }
                    else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } label: { ActionLabel(title: "Add from Photos", icon: "plus") }
                .buttonStyle(.plain).disabled(vault.busy).accessibilityIdentifier("addToVault")
            if library.status == .limited {
                Button("Manage photo access") {
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: anchor) { _ in Task { @MainActor in library.refresh() } }
                }
            }
            if vault.busy { ProgressView(vault.progress).frame(maxWidth: .infinity) }
            if !vault.recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Verified copies · \(vault.recent.count)", systemImage: "checkmark.shield")
                        .font(.headline).accessibilityIdentifier("verifiedCopies")
                    Text("The originals are still in Photos. " + deletionNote).font(.caption)
                    let candidates = vault.recent.filter { !$0.favorite }
                    if !candidates.isEmpty {
                        Button("Remove originals from Photos (\(candidates.count))", role: .destructive) {
                            Task { await vault.deleteOriginals(candidates) }
                        }.accessibilityIdentifier("deleteVaultOriginals")
                    }
                    Button("Keep originals") { vault.dismissReceipt() }
                }.padding(16).background(Color.lane, in: RoundedRectangle(cornerRadius: 16)).disabled(vault.busy)
            }
            if vault.photos.isEmpty {
                Text("Add your first photos. After verification, you can remove their originals from Photos.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(vault.photos) { photo in
                        Button { detail = photo } label: {
                            VaultImage(photo: photo, fill: true).frame(height: 150)
                                .overlay(alignment: .bottomLeading) {
                                    Label(photo.live ? "Live Photo" : "Photo", systemImage: photo.live ? "livephoto" : "photo")
                                        .font(.caption.bold()).padding(6).background(.black.opacity(0.72), in: Capsule()).padding(6)
                                }.clipShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(vault.busy)
                            .accessibilityIdentifier(photo.live ? "vaultLiveTile" : "vaultPhotoTile")
                    }
                }
            }
        }
    }
    private func detailView(_ photo: VaultPhoto) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("All photos", systemImage: "chevron.left") { detail = nil }
            Text(photo.live ? "Live Photo" : "Photo").font(.title.bold())
            if photo.live { VaultMotionPlayer(photo: photo).frame(height: 270) }
            else { VaultImage(photo: photo, fill: false).frame(height: 270) }
            if let date = photo.date { Text(date.formatted(.dateTime.month(.wide).day().year().hour().minute().locale(Locale(identifier: "en_US")))).font(.caption) }
            Button { Task { await vault.export(photo) } } label: {
                ActionLabel(title: "Restore to Photos", icon: "square.and.arrow.up")
            }.buttonStyle(.plain).accessibilityIdentifier("exportVaultPhoto")
            Text("A copy will appear in Photos. Your vault copy stays here.").font(.caption).foregroundStyle(.secondary)
            if !photo.favorite, PHAsset.fetchAssets(withLocalIdentifiers: [photo.sourceID], options: nil).count == 1 {
                Divider()
                Text(deletionNote).font(.caption).foregroundStyle(.secondary)
                Button("Remove original from Photos", role: .destructive) { Task { await vault.deleteOriginals([photo]) } }
            }
            if vault.busy { ProgressView(vault.progress) }
        }.disabled(vault.busy)
    }
}

struct VaultImage: View {
    @EnvironmentObject private var vault: VaultStore
    let photo: VaultPhoto
    let fill: Bool
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { bounds in
            ZStack {
                Color.lane
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                } else { Image(systemName: "photo") }
            }.frame(width: bounds.size.width, height: bounds.size.height).clipped()
        }.task(id: photo.id) { image = await vault.thumbnail(photo) }
    }
}

private struct VaultPicker: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    let importSelection: ([PHAsset]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose photos or Live Photos. Originals in iCloud may take longer to download.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if library.months.isEmpty {
                        Text(library.loading ? "Loading photos…" : "No photos available").padding(.vertical)
                    }
                    ForEach(library.months, id: \.self) { month in
                        Text("\(month.name) \(String(month.year))").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                            ForEach(library.assets(in: month), id: \.localIdentifier) { asset in
                                let id = asset.localIdentifier
                                Button {
                                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                                } label: {
                                    AssetImage(asset: asset, pixels: 300).frame(height: 108)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected.contains(id) ? Color.track : .white).padding(5)
                                                .background(.black.opacity(0.6), in: Circle()).padding(4)
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            if asset.mediaSubtypes.contains(.photoLive) { Image(systemName: "livephoto").padding(4) }
                                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityLabel(asset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo")
                                    .accessibilityAddTraits(selected.contains(id) ? .isSelected : []).accessibilityIdentifier("pick-" + id)
                            }
                        }
                    }
                }.padding(16)
            }.navigationTitle("Add to vault").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") {
                        importSelection(library.months.flatMap { library.assets(in: $0) }.filter { selected.contains($0.localIdentifier) })
                    }.disabled(selected.isEmpty).accessibilityIdentifier("importVaultSelection")
                }
            }
        }
    }
}
