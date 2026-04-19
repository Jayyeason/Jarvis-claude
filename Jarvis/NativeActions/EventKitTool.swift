import EventKit
import CoreLocation

@MainActor
class EventKitTool {
    static let shared = EventKitTool()

    private let store = EKEventStore()

    func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToEvents()
            try await store.requestFullAccessToReminders()
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let error { continuation.resume(throwing: error); return }
                    if !granted { continuation.resume(throwing: EventKitError.accessDenied); return }
                    continuation.resume()
                }
            }
        }
    }

    func createEvent(result: RecognitionResult, latitude: Double? = nil, longitude: Double? = nil) async throws {
        try await requestAccess()

        let event = EKEvent(eventStore: store)
        event.title = result.title ?? "新日程"
        event.startDate = result.startTime ?? Date()
        event.endDate = result.endTime ?? (result.startTime?.addingTimeInterval(3600) ?? Date().addingTimeInterval(3600))
        event.notes = result.notes
        event.calendar = store.defaultCalendarForNewEvents

        if let loc = result.location {
            event.location = loc
        }

        if let lat = latitude, let lon = longitude {
            let structured = EKStructuredLocation(title: result.location ?? "")
            structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
            event.structuredLocation = structured
        }

        let alarm = EKAlarm(relativeOffset: -30 * 60)
        event.addAlarm(alarm)

        try store.save(event, span: .thisEvent)
    }

    func createReminder(result: RecognitionResult) async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToReminders()
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error { continuation.resume(throwing: error); return }
                    if !granted { continuation.resume(throwing: EventKitError.accessDenied); return }
                    continuation.resume()
                }
            }
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = result.title ?? "新提醒"
        reminder.notes = result.notes
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let due = result.dueDate {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day], from: due
            )
            if let timeStr = result.dueTime {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2 {
                    components.hour = parts[0]
                    components.minute = parts[1]
                }
            }
            reminder.dueDateComponents = components
        }

        try store.save(reminder, commit: true)
    }
}

enum EventKitError: Error, LocalizedError {
    case accessDenied
    var errorDescription: String? { "日历/提醒事项访问被拒绝，请在系统设置中授权" }
}
