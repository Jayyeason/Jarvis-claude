import Foundation

struct ChatResponse: Codable {
    var type: String
    var calendar: CalendarResponse?
    var reminder: ReminderResponse?
    var reply: String?
    var error: String?
}

struct CalendarResponse: Codable {
    var title: String?
    var notes: String?
    var location: String?
    var startTime: String?
    var endTime: String?
    var isAllDay: Bool?
    var needsDuration: Bool?
    var recurrence: RecurrenceResponse?
    var travelTimeMinutes: Int?
    var alertMinutesBeforeStart: Int?
    var calendarName: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case title, notes, location, recurrence, url
        case startTime = "start_time"
        case endTime = "end_time"
        case isAllDay = "is_all_day"
        case needsDuration = "needs_duration"
        case travelTimeMinutes = "travel_time_minutes"
        case alertMinutesBeforeStart = "alert_minutes_before_start"
        case calendarName = "calendar_name"
    }
}

struct ReminderResponse: Codable {
    var title: String?
    var notes: String?
    var location: String?
    var dueDate: String?
    var dueTime: String?
    var recurrence: RecurrenceResponse?
    var alertMinutesBeforeDue: Int?
    var listName: String?
    var priority: String?
    var flagged: Bool?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case title, notes, location, recurrence, priority, flagged, url
        case dueDate = "due_date"
        case dueTime = "due_time"
        case alertMinutesBeforeDue = "alert_minutes_before_due"
        case listName = "list_name"
    }
}

struct RecurrenceResponse: Codable {
    var frequency: String
    var interval: Int?
    var weekdays: [String]?
    var endDate: String?
    var occurrenceCount: Int?

    enum CodingKeys: String, CodingKey {
        case frequency, interval, weekdays
        case endDate = "end_date"
        case occurrenceCount = "occurrence_count"
    }
}
