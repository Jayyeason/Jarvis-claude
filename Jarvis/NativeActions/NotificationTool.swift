import Foundation
import UserNotifications

@MainActor
class NotificationTool {
    static let shared = NotificationTool()

    private var requested = false

    func send(_ event: ProactiveEvent) async {
        do {
            if !requested {
                requested = true
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: event.id,
                content: content,
                trigger: nil
            )
            try await UNUserNotificationCenter.current().add(request)
            jlog("[Notification] sent id=\(event.id)")
        } catch {
            jlog("[Notification] send failed id=\(event.id) error=\(error.localizedDescription)")
        }
    }
}
