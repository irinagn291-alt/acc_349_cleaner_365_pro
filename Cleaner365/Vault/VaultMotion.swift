import PhotosUI
import SwiftUI

/// PhotoKit may read the pair throughout playback. Release both files with the player.
final class VaultMotion {
    let photo: PHLivePhoto
    private let folder: URL
    init(photo: PHLivePhoto, folder: URL) { self.photo = photo; self.folder = folder }
    deinit { try? FileManager.default.removeItem(at: folder) }
}

struct VaultMotionPlayer: View {
    @EnvironmentObject private var vault: VaultStore
    let photo: VaultPhoto
    @State private var requested = false
    @State private var motion: VaultMotion?
    var body: some View {
        ZStack {
            if let motion { Player(motion: motion).accessibilityIdentifier("vaultMotionPlayer") }
            else {
                VaultImage(photo: photo, fill: false)
                if requested { ProgressView() }
                else {
                    Button { requested = true } label: {
                        Label("Play motion", systemImage: "livephoto.play")
                            .padding(10).background(.black.opacity(0.75), in: Capsule())
                    }.accessibilityIdentifier("playVaultMotion")
                }
            }
        }
        .task(id: requested) {
            guard requested else { return }
            do { motion = try await vault.motion(photo) }
            catch {
                if !Task.isCancelled && vault.unlocked { requested = false; vault.notice = (error as? VaultError)?.errorDescription ?? "Could not play this Live Photo." }
            }
        }
        .onDisappear { motion = nil; requested = false }
    }
    private struct Player: UIViewRepresentable {
        let motion: VaultMotion
        func makeUIView(context: Context) -> PHLivePhotoView {
            let view = PHLivePhotoView()
            view.contentMode = .scaleAspectFit
            view.livePhoto = motion.photo
            view.startPlayback(with: .full)
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Live Photo"
            return view
        }
        func updateUIView(_ uiView: PHLivePhotoView, context: Context) {}
        static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: ()) {
            uiView.stopPlayback()
            uiView.livePhoto = nil
        }
    }
}
