import UIKit
import Combine

/// Cover every app window, including presented players/Quick Look, before snapshots.
@MainActor
final class PrivacyShield: NSObject, ObservableObject {
    var shouldCover: () -> Bool = { false }
    private var covers: [UIView] = []
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,selector: #selector(cover),name: UIApplication.willResignActiveNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(uncover),name: UIApplication.didBecomeActiveNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(sceneCover(_:)),name: UIScene.willDeactivateNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(sceneUncover(_:)),name: UIScene.didActivateNotification,object: nil)
    }
    @objc private func cover() {
        guard shouldCover() else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) { coverWindows(scene.windows) }
    }
    @objc private func sceneCover(_ notification: Notification) {
        guard shouldCover(), let scene = notification.object as? UIWindowScene else { return }
        coverWindows(scene.windows)
    }
    private func coverWindows(_ windows: [UIWindow]) {
        for window in windows where !window.isHidden && !covers.contains(where: { $0.superview === window }) {
            let cover = UIView(frame: window.bounds)
            cover.autoresizingMask = [.flexibleWidth,.flexibleHeight]
            cover.backgroundColor = .black
            cover.isUserInteractionEnabled = true
            cover.layer.zPosition = 1_000_000
            let icon = UIImageView(image: UIImage(systemName: "lock.shield",withConfiguration: UIImage.SymbolConfiguration(pointSize: 54,weight: .light)))
            icon.tintColor = UIColor(red: 0.81, green: 0.98, blue: 0.27, alpha: 1)
            icon.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(icon)
            NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
            window.addSubview(cover); covers.append(cover)
        }
    }
    @objc private func uncover() {
        covers.removeAll { view in
            guard view.window?.windowScene?.activationState == .foregroundActive else { return false }
            view.removeFromSuperview(); return true
        }
    }
    @objc private func sceneUncover(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        covers.removeAll { view in
            guard view.window?.windowScene === scene else { return false }
            view.removeFromSuperview(); return true
        }
    }
}
