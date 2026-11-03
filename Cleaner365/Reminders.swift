import SwiftUI
import UserNotifications

@MainActor final class ReviewRoute: ObservableObject {
    static let shared = ReviewRoute()
    @Published var requested = false
}

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.identifier == ReminderSettings.identifier {
            await MainActor.run { ReviewRoute.shared.requested = true }
        }
    }
}

struct ReminderSettings: View {
    nonisolated static let identifier = "cleaner365.monthly"
    nonisolated static func request() -> UNNotificationRequest {
        var date = DateComponents()
        date.day = 1; date.hour = 19; date.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "Your monthly photo round"
        content.body = "Pick up where you left off in Cleaner 365."
        content.interruptionLevel = .passive
        return UNNotificationRequest(identifier: identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
    }
    @State private var enabled = false
    @State private var processing = true
    @State private var denied = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scene

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TimingLabel("365 / YOUR ROUTINE").foregroundStyle(Color.track)
            Text("Reminders").font(.largeTitle.bold())
            Toggle("Monthly review", isOn: Binding(get: { enabled }, set: { value in
                processing = true
                Task { await set(value) }
            })).accessibilityIdentifier("monthlyReminder").disabled(processing)
            Text("One quiet reminder on the first of each month at 7 PM, local time. No sound or badge.")
                .font(.subheadline).foregroundStyle(.secondary)
            if denied { Button("Notification settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } }
            if let message { Text(message).font(.caption) }
            Spacer()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.asphalt)
        .task { await refresh() }
        .onChange(of: scene) { _, phase in if phase == .active && !processing { Task { await refresh() } } }
    }
    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        denied = await center.notificationSettings().authorizationStatus == .denied
        let scheduled = await center.pendingNotificationRequests().contains { $0.identifier == Self.identifier }
        enabled = !denied && scheduled
        processing = false
    }
    private func set(_ value: Bool) async {
        let center = UNUserNotificationCenter.current()
        message = nil
        if value {
            do {
                if try await center.requestAuthorization(options: [.alert]) {
                    try await center.add(Self.request())
                } else { message = "Allow notifications in Settings to schedule your reminder." }
            } catch { message = "Could not schedule the reminder. Try again." }
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        }
        await refresh()
    }
}
