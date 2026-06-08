import EventKit
import CoreLocation

@MainActor
class EventKitTool {
    static let shared = EventKitTool()

    private let defaultReminderListName = "提醒事项"
    private let store = EKEventStore()

    func requestAccess() async throws {
        try await requestEventAccess()
        try await requestReminderAccess()
    }

    private func requestEventAccess() async throws {
        let before = Self.authorizationDescription(for: .event)
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            let after = Self.authorizationDescription(for: .event)
            jlog("[EventKit] request event access before=\(before) after=\(after) granted=\(granted)")
            guard granted, Self.hasFullAccess(to: .event) else {
                throw EventKitError.accessDeniedStatus("日历当前状态：\(after)")
            }
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
        let before = Self.authorizationDescription(for: .reminder)
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToReminders()
            let after = Self.authorizationDescription(for: .reminder)
            jlog("[EventKit] request reminder access before=\(before) after=\(after) granted=\(granted)")
            guard granted, Self.hasFullAccess(to: .reminder) else {
                throw EventKitError.accessDeniedStatus("提醒事项当前状态：\(after)")
            }
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

    @discardableResult
    func createEvent(result: CalendarRecognition, selectedLocation: LocationResult? = nil) async throws -> CalendarEventSnapshot {
        try await requestEventAccess()

        guard let cal = eventCalendar(named: result.calendarName) else {
            jlog("[EventKit] no writable event calendar. calendars=\(eventCalendarInventory())")
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

        jlog("[EventKit] saving event title=\(result.title) start=\(isoString(startDate)) end=\(isoString(endDate)) calendar={\(calendarDescription(cal))}")
        try store.save(event, span: .thisEvent, commit: true)

        let verified = await verifySavedEvent(event, title: result.title, start: startDate, end: endDate, calendar: cal)
        guard let verified else {
            let eventID = event.eventIdentifier ?? "nil"
            jlog("[EventKit] event save verification failed title=\(result.title) id=\(eventID) calendar={\(calendarDescription(cal))}")
            throw EventKitError.eventSaveVerificationFailed
        }

        jlog("[EventKit] event saved verified id=\(verified.eventIdentifier ?? "nil") calendar={\(calendarDescription(verified.calendar))}")
        return CalendarEventSnapshot(
            id: verified.eventIdentifier ?? event.eventIdentifier ?? UUID().uuidString,
            title: verified.title ?? result.title,
            startTime: isoString(verified.startDate),
            endTime: isoString(verified.endDate),
            isAllDay: verified.isAllDay,
            location: verified.location,
            calendarName: verified.calendar?.title ?? cal.title,
            alertMinutesBeforeStart: eventAlertMinutesBeforeStart(verified)
        )
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

    func queryEvents(start: Date?, end: Date?, keywords: [String]) async throws -> [CalendarEventSnapshot] {
        try await requestEventAccess()
        let range = normalizedEventRange(start: start, end: end)
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { event in
                event.startDate < range.end && event.endDate > range.start
            }
            .filter { event in
                matchesKeywords(event.title ?? "", keywords: keywords)
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEventSnapshot(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "无标题",
                    startTime: isoString(event.startDate),
                    endTime: isoString(event.endDate),
                    isAllDay: event.isAllDay,
                    location: event.location,
                    calendarName: event.calendar?.title,
                    alertMinutesBeforeStart: eventAlertMinutesBeforeStart(event)
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

    func updateEvents(ids: [String], patch: AssistantOperationPatch) async throws {
        try await requestEventAccess()
        var updatedAny = false
        for id in Set(ids) {
            guard let event = store.event(withIdentifier: id) else { continue }

            let originalStart = event.startDate ?? Date()
            let originalEnd = event.endDate ?? originalStart.addingTimeInterval(3600)
            let duration = max(originalEnd.timeIntervalSince(originalStart), 60)

            if let title = patch.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                event.title = title
            }
            if let location = patch.location {
                event.location = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location
            }

            if let shift = patch.shiftMinutes {
                let offset = TimeInterval(shift * 60)
                event.startDate = originalStart.addingTimeInterval(offset)
                event.endDate = originalEnd.addingTimeInterval(offset)
            } else if let newStart = parseFlexibleDateTime(patch.newStartTime, baseDate: originalStart) {
                event.startDate = newStart
                if let newEnd = parseFlexibleDateTime(patch.newEndTime, baseDate: newStart) {
                    event.endDate = newEnd > newStart ? newEnd : newStart.addingTimeInterval(duration)
                } else {
                    event.endDate = newStart.addingTimeInterval(duration)
                }
            } else if let newEnd = parseFlexibleDateTime(patch.newEndTime, baseDate: originalEnd) {
                event.endDate = newEnd
            }

            if event.endDate <= event.startDate {
                event.endDate = event.startDate.addingTimeInterval(duration)
            }

            try store.save(event, span: .thisEvent, commit: false)
            updatedAny = true
        }
        guard updatedAny else {
            throw EventKitError.eventNotFound
        }
        try store.commit()
    }

    func updateEventAlerts(ids: [String], minutesBeforeStart: Int) async throws {
        try await requestEventAccess()
        var updatedAny = false
        for id in Set(ids) {
            guard let event = store.event(withIdentifier: id) else { continue }
            replaceAlarms(on: event, with: EKAlarm(relativeOffset: TimeInterval(-max(minutesBeforeStart, 0) * 60)))
            try store.save(event, span: .thisEvent, commit: false)
            updatedAny = true
        }
        guard updatedAny else {
            throw EventKitError.eventNotFound
        }
        try store.commit()
    }

    func createReminder(result: ReminderRecognition, selectedLocation: LocationResult? = nil) async throws {
        try await requestReminderAccess()

        guard let calendar = reminderCalendar(named: defaultReminderListName) else {
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
               Calendar.current.date(from: components) != nil {
                reminder.addAlarm(reminderAlarm(minutesBeforeDue: minutes))
            }
        }

        if let rule = makeRecurrenceRule(from: result.recurrence) {
            reminder.addRecurrenceRule(rule)
        }

        try store.save(reminder, commit: true)
    }

    func queryReminders(start: Date?, end: Date?, keywords: [String], includeCompleted: Bool = false) async throws -> [ReminderSnapshot] {
        try await requestReminderAccess()
        let predicate = store.predicateForReminders(in: nil)
        let reminders = try await fetchReminders(matching: predicate)
        return reminders
            .filter { includeCompleted || !$0.isCompleted }
            .filter { reminder in
                matchesKeywords(reminder.title ?? "", keywords: keywords)
            }
            .filter { reminder in
                guard let start, let end else { return true }
                guard let due = reminderDueDate(reminder) else { return false }
                return due >= start && due < end
            }
            .sorted { lhs, rhs in
                (reminderDueDate(lhs) ?? Date.distantFuture) < (reminderDueDate(rhs) ?? Date.distantFuture)
            }
            .map { reminder in
                ReminderSnapshot(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "无标题",
                    dueDate: optionalDateString(reminderDueDate(reminder)),
                    dueTime: reminderDueTimeString(reminder),
                    isCompleted: reminder.isCompleted,
                    priority: reminder.priority,
                    listName: reminder.calendar.title,
                    alertMinutesBeforeDue: reminderAlertMinutesBeforeDue(reminder)
                )
            }
    }

    func deleteReminders(ids: [String]) async throws {
        try await requestReminderAccess()
        var deletedAny = false
        for id in Set(ids) {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            try store.remove(reminder, commit: false)
            deletedAny = true
        }
        guard deletedAny else {
            throw EventKitError.reminderNotFound
        }
        try store.commit()
    }

    func updateReminders(ids: [String], patch: AssistantOperationPatch) async throws {
        try await requestReminderAccess()
        var updatedAny = false
        for id in Set(ids) {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            let existingAlertMinutes = reminderAlertMinutesBeforeDue(reminder)

            if let title = patch.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reminder.title = title
            }
            if let location = patch.location {
                reminder.location = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location
            }

            if let shift = patch.shiftMinutes, let due = reminderDueDate(reminder) {
                reminder.dueDateComponents = reminderComponents(from: due.addingTimeInterval(TimeInterval(shift * 60)))
            } else {
                let base = reminderDueDate(reminder) ?? Date()
                let dateValue = patch.newDueDate.flatMap { parseDateOnly($0) }
                let timeValue = patch.newDueTime ?? patch.newStartTime
                if let fullDate = parseFlexibleDateTime(timeValue, baseDate: dateValue ?? base) {
                    reminder.dueDateComponents = reminderComponents(from: fullDate)
                } else if let dateValue {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: dateValue)
                    let existing = reminder.dueDateComponents
                    components.hour = existing?.hour
                    components.minute = existing?.minute
                    reminder.dueDateComponents = components
                }
            }

            if let existingAlertMinutes, reminderDueDate(reminder) != nil {
                replaceAlarms(on: reminder, with: reminderAlarm(minutesBeforeDue: existingAlertMinutes))
            }
            try store.save(reminder, commit: false)
            updatedAny = true
        }
        guard updatedAny else {
            throw EventKitError.reminderNotFound
        }
        try store.commit()
    }

    func updateReminderAlerts(ids: [String], minutesBeforeDue: Int) async throws {
        try await requestReminderAccess()
        var updatedAny = false
        for id in Set(ids) {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            guard reminderDueDate(reminder) != nil else { throw EventKitError.missingReminderDueDate }
            replaceAlarms(on: reminder, with: reminderAlarm(minutesBeforeDue: minutesBeforeDue))
            try store.save(reminder, commit: false)
            updatedAny = true
        }
        guard updatedAny else {
            throw EventKitError.reminderNotFound
        }
        try store.commit()
    }

    private func eventCalendar(named requestedName: String?) -> EKCalendar? {
        let calendars = store.calendars(for: .event)
        let writable = calendars.filter(isWritableUserEventCalendar)
        let requested = requestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requested, !requested.isEmpty {
            if let exact = writable.first(where: { $0.title == requested }) {
                return exact
            }
            if let loose = writable.first(where: { $0.title.localizedCaseInsensitiveContains(requested) }) {
                return loose
            }
        }

        if let defaultCalendar = store.defaultCalendarForNewEvents,
           isWritableUserEventCalendar(defaultCalendar) {
            return defaultCalendar
        }

        return writable.first(where: { $0.type == .local })
            ?? writable.first
            ?? calendars.first(where: { $0.allowsContentModifications })
    }

    private func reminderCalendar(named name: String) -> EKCalendar? {
        let named = store.calendars(for: .reminder).first {
            $0.title == name && $0.allowsContentModifications
        }
        return named
            ?? store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
    }

    private func isWritableUserEventCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.allowsContentModifications
            && calendar.type != .birthday
            && calendar.type != .subscription
    }

    private func verifySavedEvent(_ event: EKEvent, title: String, start: Date, end: Date, calendar: EKCalendar) async -> EKEvent? {
        if let identifier = event.eventIdentifier,
           let byID = store.event(withIdentifier: identifier) {
            return byID
        }

        if let bySearch = matchingSavedEvent(title: title, start: start, end: end, calendars: [calendar]) {
            return bySearch
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        if let identifier = event.eventIdentifier,
           let byID = store.event(withIdentifier: identifier) {
            return byID
        }
        return matchingSavedEvent(title: title, start: start, end: end, calendars: [calendar])
            ?? matchingSavedEvent(title: title, start: start, end: end, calendars: nil)
    }

    private func matchingSavedEvent(title: String, start: Date, end: Date, calendars: [EKCalendar]?) -> EKEvent? {
        let queryStart = start.addingTimeInterval(-60)
        let queryEnd = max(end, start.addingTimeInterval(60)).addingTimeInterval(60)
        let predicate = store.predicateForEvents(withStart: queryStart, end: queryEnd, calendars: calendars)
        return store.events(matching: predicate).first { event in
            guard (event.title ?? "") == title else { return false }
            let startDelta = abs(event.startDate.timeIntervalSince(start))
            let endDelta = abs(event.endDate.timeIntervalSince(end))
            return startDelta < 60 && endDelta < 60
        }
    }

    private func eventCalendarInventory() -> String {
        store.calendars(for: .event)
            .map { calendarDescription($0) }
            .joined(separator: "; ")
    }

    private func calendarDescription(_ calendar: EKCalendar?) -> String {
        guard let calendar else { return "nil" }
        let sourceTitle = calendar.source?.title ?? "unknown"
        return "title=\(calendar.title), id=\(calendar.calendarIdentifier), type=\(calendarTypeDescription(calendar.type)), source=\(sourceTitle), allows=\(calendar.allowsContentModifications)"
    }

    private func calendarTypeDescription(_ type: EKCalendarType) -> String {
        switch type {
        case .local: return "local"
        case .calDAV: return "calDAV"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }

    private func replaceAlarms(on item: EKCalendarItem, with alarm: EKAlarm) {
        for existing in item.alarms ?? [] {
            item.removeAlarm(existing)
        }
        item.addAlarm(alarm)
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
        guard let due = reminderDueDate(reminder) else { return nil }
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

    private func reminderAlarm(minutesBeforeDue: Int) -> EKAlarm {
        EKAlarm(relativeOffset: TimeInterval(-max(minutesBeforeDue, 0) * 60))
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

    private func normalizedEventRange(start: Date?, end: Date?) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let lower = start ?? calendar.startOfDay(for: Date())
        let upper = end ?? calendar.date(byAdding: .day, value: 30, to: lower) ?? lower.addingTimeInterval(30 * 86400)
        if upper <= lower {
            return (lower, lower.addingTimeInterval(86400))
        }
        return (lower, upper)
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func matchesKeywords(_ title: String, keywords: [String]) -> Bool {
        let cleaned = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return true }
        let lowered = title.lowercased()
        return cleaned.allSatisfy { keyword in
            keywordAlternatives(for: keyword).contains { lowered.contains($0.lowercased()) }
        }
    }

    private func keywordAlternatives(for keyword: String) -> [String] {
        switch keyword.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "会议", "开会", "会":
            return ["会议", "开会", "会"]
        default:
            return [keyword]
        }
    }

    private func reminderDueDate(_ reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: components)
    }

    private func reminderDueTimeString(_ reminder: EKReminder) -> String? {
        guard let components = reminder.dueDateComponents,
              let hour = components.hour,
              let minute = components.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func reminderComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func optionalDateString(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func parseFlexibleDateTime(_ value: String?, baseDate: Date?) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }

        let normalized = raw.replacingOccurrences(of: "：", with: ":")
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: normalized) else { return nil }
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var baseComponents = calendar.dateComponents([.year, .month, .day], from: baseDate ?? Date())
        baseComponents.hour = timeComponents.hour
        baseComponents.minute = timeComponents.minute
        return calendar.date(from: baseComponents)
    }

    static func hasFullAccess(to entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        return status == .authorized || status == .fullAccess
    }

    static func authorizationDescription(for entityType: EKEntityType) -> String {
        let status = EKEventStore.authorizationStatus(for: entityType)
        switch status {
        case .notDetermined:
            return "notDetermined(\(status.rawValue))"
        case .restricted:
            return "restricted(\(status.rawValue))"
        case .denied:
            return "denied(\(status.rawValue))"
        case .authorized:
            return "authorized(\(status.rawValue))"
        case .fullAccess:
            return "fullAccess(\(status.rawValue))"
        case .writeOnly:
            return "writeOnly(\(status.rawValue))"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }
}

enum EventKitError: Error, LocalizedError {
    case accessDenied
    case accessDeniedStatus(String)
    case noCalendar
    case noReminderCalendar
    case missingStartTime
    case eventNotFound
    case eventSaveVerificationFailed
    case reminderNotFound
    case missingReminderDueDate

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "日历/提醒事项访问被拒绝，请在系统设置中授权"
        case .accessDeniedStatus(let status): return "Jarvis 当前没有完整日历/提醒事项访问权限（\(status)）。请在系统设置 > 隐私与安全性 > 日历/提醒事项中授权 Jarvis，然后重启 Jarvis。"
        case .noCalendar: return "找不到可用的日历，请在日历 app 中创建一个"
        case .noReminderCalendar: return "找不到默认提醒事项列表"
        case .missingStartTime: return "日程缺少开始时间，请补充后再写入"
        case .eventNotFound: return "找不到匹配的日程"
        case .eventSaveVerificationFailed: return "日程保存后没有在系统日历中查到，Jarvis 已停止显示成功结果。请检查系统设置中的日历完整访问权限后重试。"
        case .reminderNotFound: return "找不到匹配的待办"
        case .missingReminderDueDate: return "待办没有到期时间，无法设置提前提醒"
        }
    }
}
