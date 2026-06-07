import EventKit
import CoreLocation

@MainActor
class EventKitTool {
    static let shared = EventKitTool()

    private let store = EKEventStore()

    func requestAccess() async throws {
        try await requestEventAccess()
        try await requestReminderAccess()
    }

    private func requestEventAccess() async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToEvents()
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

    private func requestReminderAccess() async throws {
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
    }

    func createEvent(result: CalendarRecognition, selectedLocation: LocationResult? = nil) async throws {
        try await requestEventAccess()

        guard let cal = eventCalendar(named: result.calendarName) else {
            throw EventKitError.noCalendar
        }

        guard let startDate = result.startTime else {
            throw EventKitError.missingStartTime
        }
        var endDate = result.endTime ?? startDate.addingTimeInterval(3600)
        if result.isAllDay && endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
        }

        let event = EKEvent(eventStore: store)
        event.title = result.title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = result.isAllDay
        event.notes = result.notes
        event.calendar = cal
        event.url = result.url

        let locationTitle = selectedLocation?.name ?? result.location
        if let locationTitle, !locationTitle.isEmpty {
            event.location = locationTitle
        }

        if let selectedLocation,
           selectedLocation.latitude != 0 || selectedLocation.longitude != 0 {
            let structured = EKStructuredLocation(title: selectedLocation.name)
            structured.geoLocation = CLLocation(latitude: selectedLocation.latitude, longitude: selectedLocation.longitude)
            event.structuredLocation = structured
        }

        if result.alertMinutesBeforeStart >= 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-result.alertMinutesBeforeStart * 60)))
        }

        if let rule = makeRecurrenceRule(from: result.recurrence) {
            event.addRecurrenceRule(rule)
        }

        try store.save(event, span: .thisEvent)
    }

    func checkConflicts(start: Date, end: Date) async throws -> [ConflictInfo] {
        try await requestEventAccess()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay else { return false }
                return event.startDate < end && event.endDate > start
            }
            .map { event in
                ConflictInfo(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "无标题",
                    startTime: isoString(event.startDate),
                    endTime: isoString(event.endDate),
                    calendarName: event.calendar?.title
                )
            }
    }

    func deleteEvents(ids: [String]) async throws {
        try await requestEventAccess()
        var deletedAny = false
        for id in Set(ids) {
            guard let event = store.event(withIdentifier: id) else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
            deletedAny = true
        }
        guard deletedAny else {
            throw EventKitError.eventNotFound
        }
        try store.commit()
    }

    func createReminder(result: ReminderRecognition, selectedLocation: LocationResult? = nil) async throws {
        try await requestReminderAccess()

        guard let calendar = reminderCalendar(named: result.listName) else {
            throw EventKitError.noReminderCalendar
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = result.title
        reminder.notes = result.notes
        reminder.calendar = calendar
        reminder.url = result.url
        reminder.location = selectedLocation?.name ?? result.location
        reminder.priority = priorityValue(result.priority)

        if let due = result.dueDate {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
            if let timeStr = result.dueTime {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2 {
                    components.hour = parts[0]
                    components.minute = parts[1]
                }
            }
            reminder.dueDateComponents = components

            if let minutes = result.alertMinutesBeforeDue,
               let dueDate = Calendar.current.date(from: components) {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate.addingTimeInterval(TimeInterval(-minutes * 60))))
            }
        }

        if let rule = makeRecurrenceRule(from: result.recurrence) {
            reminder.addRecurrenceRule(rule)
        }

        try store.save(reminder, commit: true)
    }

    private func eventCalendar(named name: String?) -> EKCalendar? {
        if let name, !name.isEmpty {
            let match = store.calendars(for: .event).first {
                $0.title == name && $0.allowsContentModifications
            }
            if let match { return match }
        }
        return store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
    }

    private func reminderCalendar(named name: String?) -> EKCalendar? {
        if let name, !name.isEmpty {
            let match = store.calendars(for: .reminder).first {
                $0.title == name && $0.allowsContentModifications
            }
            if let match { return match }
        }
        return store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
    }

    private func priorityValue(_ priority: String) -> Int {
        switch priority {
        case "high": return 1
        case "medium": return 5
        case "low": return 9
        default: return 0
        }
    }

    private func makeRecurrenceRule(from recurrence: RecurrenceRule?) -> EKRecurrenceRule? {
        guard let recurrence else { return nil }

        let frequency: EKRecurrenceFrequency
        switch recurrence.frequency {
        case "daily": frequency = .daily
        case "weekly": frequency = .weekly
        case "monthly": frequency = .monthly
        case "yearly": frequency = .yearly
        default: return nil
        }

        let end: EKRecurrenceEnd?
        if let count = recurrence.occurrenceCount, count > 0 {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if let date = recurrence.endDate {
            end = EKRecurrenceEnd(end: date)
        } else {
            end = nil
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(recurrence.interval, 1),
            daysOfTheWeek: recurrence.weekdays?.compactMap(makeWeekday),
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private func makeWeekday(_ value: String) -> EKRecurrenceDayOfWeek? {
        switch value {
        case "monday": return EKRecurrenceDayOfWeek(.monday)
        case "tuesday": return EKRecurrenceDayOfWeek(.tuesday)
        case "wednesday": return EKRecurrenceDayOfWeek(.wednesday)
        case "thursday": return EKRecurrenceDayOfWeek(.thursday)
        case "friday": return EKRecurrenceDayOfWeek(.friday)
        case "saturday": return EKRecurrenceDayOfWeek(.saturday)
        case "sunday": return EKRecurrenceDayOfWeek(.sunday)
        default: return nil
        }
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum EventKitError: Error, LocalizedError {
    case accessDenied
    case noCalendar
    case noReminderCalendar
    case missingStartTime
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "日历/提醒事项访问被拒绝，请在系统设置中授权"
        case .noCalendar: return "找不到可用的日历，请在日历 app 中创建一个"
        case .noReminderCalendar: return "找不到默认提醒事项列表"
        case .missingStartTime: return "日程缺少开始时间，请补充后再写入"
        case .eventNotFound: return "找不到要替换的旧行程"
        }
    }
}
