import EventKit
import Combine
import Foundation

struct CalendarEventItem: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: CGColor
    let location: String?
}

struct ReminderItem: Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    let priority: Int
    let calendarColor: CGColor
    let ekReminder: EKReminder
}

@MainActor
class TaskListStore: ObservableObject {
    static let shared = TaskListStore()

    @Published var todayEvents: [CalendarEventItem] = []
    @Published var upcomingEvents: [CalendarEventItem] = []
    @Published var incompleteReminders: [ReminderItem] = []
    @Published var completedReminders: [ReminderItem] = []
    @Published var isLoading = false

    private let store = EKEventStore()

    func reload() {
        Task { await fetchAll() }
    }

    private func fetchAll() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if #available(macOS 14.0, *) {
                try await store.requestFullAccessToEvents()
                try await store.requestFullAccessToReminders()
            }
        } catch {}

        fetchEvents()
        await fetchReminders()
    }

    private func fetchEvents() {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday)!

        let predToday = store.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: nil)
        let predUpcoming = store.predicateForEvents(withStart: endOfToday, end: endOfWeek, calendars: nil)

        todayEvents = store.events(matching: predToday)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEventItem(
                id: $0.eventIdentifier,
                title: $0.title ?? "无标题",
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                calendarColor: $0.calendar.cgColor,
                location: $0.location
            )}

        upcomingEvents = store.events(matching: predUpcoming)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEventItem(
                id: $0.eventIdentifier,
                title: $0.title ?? "无标题",
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                calendarColor: $0.calendar.cgColor,
                location: $0.location
            )}
    }

    private func fetchReminders() async {
        let predicate = store.predicateForReminders(in: nil)
        let reminders = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }

        let items = reminders.map { r in
            ReminderItem(
                id: r.calendarItemIdentifier,
                title: r.title ?? "无标题",
                isCompleted: r.isCompleted,
                dueDate: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                priority: r.priority,
                calendarColor: r.calendar.cgColor,
                ekReminder: r
            )
        }

        let now = Date()
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let oneWeekLater = now.addingTimeInterval(7 * 24 * 3600)

        incompleteReminders = items
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        completedReminders = items
            .filter { $0.isCompleted }
            .filter {
                guard let due = $0.dueDate else { return false }
                return due >= oneWeekAgo && due <= oneWeekLater
            }
            .sorted { ($0.dueDate ?? .distantFuture) > ($1.dueDate ?? .distantFuture) }
    }

    func toggleReminder(_ item: ReminderItem) {
        let reminder = item.ekReminder
        reminder.isCompleted = !reminder.isCompleted
        try? store.save(reminder, commit: true)
        reload()
    }
}
