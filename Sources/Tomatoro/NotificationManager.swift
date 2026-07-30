import Foundation
import UserNotifications

/// Requests permission for and posts Tomatoro's system notifications.
@MainActor
final class NotificationManager: NSObject, @MainActor UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCountdownFinished(taskName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        content.body = "Your focus session on \"\(taskName)\" has finished."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Shows the banner even while Tomatoro is the frontmost app (macOS
    /// suppresses it by default otherwise).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
