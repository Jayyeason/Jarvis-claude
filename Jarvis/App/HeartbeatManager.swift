import AppKit
import EventKit
import Foundation

@MainActor
class HeartbeatManager {
    static let shared = HeartbeatManager()

    private let store = EKEventStore()
    private var timer: Timer?
    private var isTicking = false

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick() }
        jlog("[Heartbeat] started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        do {
            let req = try await snapshot()
            let response = try await GatewayClient.shared.heartbeatTick(req)
            for event in response.events ?? [] {
                if event.triggerType == "cron_reminder" {
                    _ = await NotificationTool.shared.send(event)
                    continue
                }
                IslandWindowController.shared.showProactive(event)
                _ = await NotificationTool.shared.send(event)
            }
        } catch {
            jlog("[Heartbeat] tick failed: \(error.localizedDescription)")
        }
    }

    private func snapshot() async throws -> HeartbeatTickRequest {
        try await requestAccess()
        let now = Date()
        return HeartbeatTickRequest(
            now: iso(now),
            appActive: NSApp.isActive,
            todayEvents: fetchEvents(dayOffset: 0),
            tomorrowEvents: fetchEvents(dayOffset: 1),
            incompleteReminders: await fetchReminders()
        )
    }

    private func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToEvents()
            try await store.requestFullAccessToReminders()
        } else {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: granted)
                }
            }
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func fetchEvents(dayOffset: Int) -> [CalendarEventSnapshot] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                CalendarEventSnapshot(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "无标题",
                    startTime: iso($0.startDate),
                    endTime: iso($0.endDate),
                    isAllDay: $0.isAllDay,
                    location: $0.location,
                    calendarName: $0.calendar?.title,
                    alertMinutesBeforeStart: eventAlertMinutesBeforeStart($0)
                )
            }
    }

    private func fetchReminders() async -> [ReminderSnapshot] {
        let predicate = store.predicateForReminders(in: nil)
        let reminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders
            .filter { !$0.isCompleted }
            .map {
                ReminderSnapshot(
                    id: $0.calendarItemIdentifier,
                    title: $0.title ?? "无标题",
                    dueDate: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map(dateOnly),
                    dueTime: reminderTime($0.dueDateComponents),
                    isCompleted: $0.isCompleted,
                    priority: $0.priority,
                    listName: $0.calendar.title,
                    alertMinutesBeforeDue: reminderAlertMinutesBeforeDue($0)
                )
            }
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func reminderTime(_ components: DateComponents?) -> String? {
        guard let hour = components?.hour, let minute = components?.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func eventAlertMinutesBeforeStart(_ event: EKEvent) -> Int? {
        let values = (event.alarms ?? []).compactMap { alarm -> Int? in
            let offset = alarm.relativeOffset
            guard offset <= 0 else { return nil }
            return max(0, Int(round(abs(offset) / 60)))
        }
        return values.min()
    }

    private func reminderAlertMinutesBeforeDue(_ reminder: EKReminder) -> Int? {
        guard let due = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) else { return nil }
        let values = (reminder.alarms ?? []).compactMap { alarm -> Int? in
            if alarm.absoluteDate == nil, alarm.relativeOffset <= 0 {
                return max(0, Int(round(abs(alarm.relativeOffset) / 60)))
            }
            guard let alertDate = alarm.absoluteDate else { return nil }
            let minutes = Int(round(due.timeIntervalSince(alertDate) / 60))
            guard minutes >= 0 else { return nil }
            return minutes
        }
        return values.min()
    }
}
