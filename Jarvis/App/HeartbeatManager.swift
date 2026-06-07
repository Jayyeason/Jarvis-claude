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
                IslandWindowController.shared.showProactive(event)
                await NotificationTool.shared.send(event)
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
                    location: $0.location
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
                    dueTime: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map(iso),
                    isCompleted: $0.isCompleted,
                    priority: $0.priority
                )
            }
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
