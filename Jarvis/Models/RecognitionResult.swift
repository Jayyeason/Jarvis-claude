import Foundation

enum RecognitionResult {
    enum EventType: String {
        case calendar, reminder
    }

    case calendar(CalendarRecognition)
    case reminder(ReminderRecognition)
    case none(reply: String?)
    case error(String?)

    var eventType: EventType? {
        switch self {
        case .calendar: return .calendar
        case .reminder: return .reminder
        case .none, .error: return nil
        }
    }

    var title: String? {
        switch self {
        case .calendar(let event): return event.title
        case .reminder(let reminder): return reminder.title
        case .none, .error: return nil
        }
    }

    var location: String? {
        switch self {
        case .calendar(let event): return event.location
        case .reminder(let reminder): return reminder.location
        case .none, .error: return nil
        }
    }

    var notes: String? {
        switch self {
        case .calendar(let event): return event.notes
        case .reminder(let reminder): return reminder.notes
        case .none, .error: return nil
        }
    }

    var startTime: Date? {
        if case .calendar(let event) = self { return event.startTime }
        return nil
    }

    var endTime: Date? {
        if case .calendar(let event) = self { return event.endTime }
        return nil
    }

    var dueDate: Date? {
        if case .reminder(let reminder) = self { return reminder.dueDate }
        return nil
    }

    var dueTime: String? {
        if case .reminder(let reminder) = self { return reminder.dueTime }
        return nil
    }

    var needsDuration: Bool {
        if case .calendar(let event) = self { return event.needsDuration }
        return false
    }

    var priority: String? {
        if case .reminder(let reminder) = self { return reminder.priority }
        return nil
    }

    var url: URL? {
        switch self {
        case .calendar(let event): return event.url
        case .reminder(let reminder): return reminder.url
        case .none, .error: return nil
        }
    }

    static func from(_ response: AgentResponse) -> RecognitionResult {
        switch response.type {
        case "batch":
            guard let first = response.candidates?.first else { return .none(reply: response.reply) }
            return from(first)
        case "none":
            return .none(reply: response.reply)
        case "error":
            return .error(response.error ?? response.reply)
        default:
            return .error("unknown_response_type:\(response.type)")
        }
    }

    static func from(_ candidate: RecognitionCandidate) -> RecognitionResult {
        switch candidate.kind {
        case "calendar":
            guard let payload = candidate.calendar else { return .error("missing_calendar_payload") }
            return .calendar(CalendarRecognition.from(payload))
        case "reminder":
            guard let payload = candidate.reminder else { return .error("missing_reminder_payload") }
            return .reminder(ReminderRecognition.from(payload))
        default:
            return .error("unknown_candidate_kind:\(candidate.kind)")
        }
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let dateTime = DateFormatter()
        dateTime.locale = Locale(identifier: "en_US_POSIX")
        dateTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = dateTime.date(from: value) { return date }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }
}

struct CalendarRecognition {
    var title: String
    var notes: String?
    var location: String?
    var startTime: Date?
    var endTime: Date?
    var isAllDay: Bool
    var needsDuration: Bool
    var recurrence: RecurrenceRule?
    var travelTimeMinutes: Int?
    var alertMinutesBeforeStart: Int
    var calendarName: String?
    var url: URL?

    static func from(_ response: CalendarPayload) -> CalendarRecognition {
        CalendarRecognition(
            title: response.title ?? "新日程",
            notes: response.notes,
            location: response.location,
            startTime: RecognitionResult.parseDate(response.startTime),
            endTime: RecognitionResult.parseDate(response.endTime),
            isAllDay: response.isAllDay ?? false,
            needsDuration: response.needsDuration ?? false,
            recurrence: response.recurrence.map(RecurrenceRule.from),
            travelTimeMinutes: response.travelTimeMinutes,
            alertMinutesBeforeStart: response.alertMinutesBeforeStart ?? 10,
            calendarName: response.calendarName,
            url: response.url.flatMap(URL.init(string:))
        )
    }
}

struct ReminderRecognition {
    var title: String
    var notes: String?
    var location: String?
    var dueDate: Date?
    var dueTime: String?
    var recurrence: RecurrenceRule?
    var alertMinutesBeforeDue: Int?
    var listName: String
    var priority: String
    var flagged: Bool
    var url: URL?

    static func from(_ response: ReminderPayload) -> ReminderRecognition {
        ReminderRecognition(
            title: response.title ?? "新提醒",
            notes: response.notes,
            location: response.location,
            dueDate: RecognitionResult.parseDate(response.dueDate),
            dueTime: response.dueTime,
            recurrence: response.recurrence.map(RecurrenceRule.from),
            alertMinutesBeforeDue: response.alertMinutesBeforeDue,
            listName: response.listName ?? "提醒事项",
            priority: response.priority ?? "none",
            flagged: response.flagged ?? false,
            url: response.url.flatMap(URL.init(string:))
        )
    }
}

struct RecurrenceRule {
    var frequency: String
    var interval: Int
    var weekdays: [String]?
    var endDate: Date?
    var occurrenceCount: Int?

    static func from(_ response: RecurrencePayload) -> RecurrenceRule {
        RecurrenceRule(
            frequency: response.frequency,
            interval: response.interval ?? 1,
            weekdays: response.weekdays,
            endDate: RecognitionResult.parseDate(response.endDate),
            occurrenceCount: response.occurrenceCount
        )
    }
}
