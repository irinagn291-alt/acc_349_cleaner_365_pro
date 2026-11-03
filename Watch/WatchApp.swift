import SwiftUI
import WatchConnectivity

final class WatchSummary: NSObject, ObservableObject, WCSessionDelegate {
    @Published var summary = ReviewSummary.read(defaults: .standard)
    @Published var status = ""
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() } }
    private func receive(_ context: [String: Any]) {
        guard let data = context["summary"] as? Data, let value = try? JSONDecoder().decode(ReviewSummary.self,from: data) else { return }
        DispatchQueue.main.async {
            guard let updated = value.updated, updated >= (self.summary.updated ?? .distantPast) else { return }
            self.summary = value
            value.write(defaults: .standard)
            self.status = ""
        }
    }
    func session(_ session: WCSession,activationDidCompleteWith activationState: WCSessionActivationState,error: Error?) {
        receive(session.receivedApplicationContext)
        sessionReachabilityDidChange(session)
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { DispatchQueue.main.async { self.refresh() } }
    }
    func session(_ session: WCSession,didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func refresh() {
        guard WCSession.default.activationState == .activated,WCSession.default.isReachable else { status = "Open Cleaner 365 on your iPhone to update."; return }
        WCSession.default.sendMessage(["request":"summary"],replyHandler: { self.receive($0) },errorHandler: { _ in DispatchQueue.main.async { self.status = "Your iPhone isn't available right now." } })
    }
}

@main
struct CleanerWatchApp: App {
    @StateObject private var model = WatchSummary()
    private let lime = Color(red: 0.81, green: 0.98, blue: 0.27)
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Label("CLEANER / 365", systemImage: "flag.checkered")
                        .font(.caption2.monospaced().bold()).foregroundStyle(lime)
                    if model.summary.updated != nil {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(model.summary.reviewed)").font(.system(.largeTitle, design: .rounded, weight: .black)).italic()
                                Text("/ \(model.summary.total)").font(.system(.title3, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
                            }
                            Text("\(model.summary.reviewed) / \(model.summary.total)").font(.headline).minimumScaleFactor(0.5)
                        }.monospacedDigit()
                        Text("Photos reviewed").font(.caption)
                        ProgressView(value: Double(model.summary.reviewed), total: Double(max(model.summary.total, 1))).tint(lime)
                            .accessibilityLabel("Review progress")
                        HStack {
                            Image(systemName: "tray")
                            Text("In review bin")
                            Spacer()
                            Text("\(model.summary.queued)").monospacedDigit().bold()
                        }.font(.caption2).padding(8).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        if let date = model.summary.updated {
                            Text("Updated \(date, style: .relative) ago").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Your first round").font(.title3.bold())
                        Text("Open Cleaner 365 on your iPhone to see your review progress.").font(.caption)
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                        .font(.caption).controlSize(.small)
                    if !model.status.isEmpty { Text(model.status).font(.caption2).foregroundStyle(.secondary) }
                }.padding(.horizontal, 3)
            }.preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "en_US"))
        }
    }
}
