import SwiftUI
import PhotosUI
import AVKit

extension Color {
    static let track = Color(red: 0.81, green: 0.98, blue: 0.27)
    static let asphalt = Color(red: 0.067, green: 0.075, blue: 0.074)
    static let lane = Color(red: 0.13, green: 0.145, blue: 0.14)
}

struct TimingLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased()).font(.caption2.monospaced().bold()).tracking(1.5)
    }
}

struct TrackMark: View {
    var body: some View {
        Canvas { context, size in
            context.translateBy(x: size.width * 0.84, y: size.height * 0.5)
            context.rotate(by: .degrees(-48))
            for lane in 0..<7 {
                let inset = CGFloat(lane) * 8
                let box = CGRect(x: -155 + inset, y: -88 + inset, width: 310 - 2*inset, height: 176 - 2*inset)
                context.stroke(Path(roundedRect: box, cornerRadius: box.height/2),
                               with: .color(.track.opacity(lane == 2 ? 0.85 : 0.35)), lineWidth: lane == 2 ? 3 : 1)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ActionLabel: View {
    let title: String
    var icon = "arrow.up.right"
    var body: some View {
        HStack { Text(title).font(.headline); Spacer(); Image(systemName: icon) }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .foregroundStyle(Color.asphalt).background(Color.track, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AssetImage: View {
    let asset: PHAsset
    var pixels: CGFloat = 480
    var fit = false
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?
    @State private var token = UUID()
    @State private var unavailable = false

    var body: some View {
        GeometryReader { frame in
            ZStack {
                Color.lane
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                } else if unavailable {
                    Image(systemName: "icloud.slash").accessibilityLabel("Preview unavailable")
                } else { ProgressView().tint(.track) }
            }.frame(width: frame.size.width, height: frame.size.height).clipped()
        }
        .onAppear { load() }
        .onChange(of: asset.localIdentifier) { load() }
        .onChange(of: asset.modificationDate) { load() }
        .onDisappear { cancel() }
    }
    private func cancel() {
        token = UUID()
        if let request { PHImageManager.default().cancelImageRequest(request); self.request = nil }
    }
    private func load() {
        cancel()
        let key = token
        image = nil
        unavailable = false
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                           contentMode: fit ? .aspectFit : .aspectFill, options: options) { result, info in
            DispatchQueue.main.async {
                guard token == key else { return }
                if let result { image = result }
                else if (info?[PHImageResultIsDegradedKey] as? Bool) != true { unavailable = true }
            }
        }
    }
}

struct PhotoPreview: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    var body: some View {
        NavigationStack {
            Group {
                if asset.mediaType == .video { ClipPreview(asset: asset) }
                else { AssetImage(asset: asset, pixels: 2400, fit: true)
                .scaleEffect(zoom)
                .gesture(MagnifyGesture().onChanged { zoom = min(max($0.magnification, 1), 4) }.onEnded { _ in zoom = 1 })
                .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1 }
                .clipped() }
            }.navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.preferredColorScheme(.dark)
    }
}

struct PickerAnchor: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private struct ClipPreview: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @State private var request: PHImageRequestID?
    @State private var generation = UUID()
    @State private var failed = false
    var body: some View {
        Group {
            if let player { VideoPlayer(player: player) }
            else if failed { ContentUnavailableView("Video unavailable", systemImage: "icloud.slash") }
            else { ProgressView("Loading video…") }
        }.onAppear {
            let token = UUID()
            generation = token
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            request = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard generation == token else { return }
                    player = item.map(AVPlayer.init(playerItem:))
                    failed = item == nil
                }
            }
        }.onDisappear {
            generation = UUID()
            if let request { PHImageManager.default().cancelImageRequest(request) }
            player?.pause(); player = nil
        }
    }
}
