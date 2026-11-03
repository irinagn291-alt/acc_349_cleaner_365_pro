import Foundation
import WatchConnectivity

final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    private var latest: ReviewSummary = .read()
    private let lock = NSLock()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func publish(_ summary: ReviewSummary) {
        lock.lock()
        latest = summary
        lock.unlock()
        if WCSession.isSupported() { push(to: .default) }
    }
    private func payload() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(latest) else { return [:] }
        return ["summary": data]
    }
    private func push(to session: WCSession) {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(payload())
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { push(to: session) }
    func sessionWatchStateDidChange(_ session: WCSession) { push(to: session) }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(payload())
    }
}
