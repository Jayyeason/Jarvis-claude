import Foundation
import UserNotifications

@MainActor
final class NotificationTool: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTool()

    private var requested = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func send(_ event: ProactiveEvent) async -> Bool {
        do {
            guard try await ensureAuthorized() else {
                jlog("[Notification] not authorized id=\(event.id)")
                return false
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
            return true
        } catch {
            jlog("[Notification] send failed id=\(event.id) error=\(error.localizedDescription)")
            return false
        }
    }

    private func ensureAuthorized() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(center)
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            guard !requested else { return false }
            requested = true
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            jlog("[Notification] authorization requested granted=\(granted)")
            return granted
        case .denied:
            jlog("[Notification] authorization denied in system settings")
            return false
        @unknown default:
            jlog("[Notification] unknown authorization status=\(settings.authorizationStatus.rawValue)")
            return false
        }
    }

    private func notificationSettings(_ center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
