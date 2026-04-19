import Foundation

struct RecognitionResult {
    enum EventType: String {
        case calendar, reminder
    }

    let eventType: EventType?
    let title: String?
    let startTime: Date?
    let endTime: Date?
    let needsDuration: Bool
    let location: String?
    let notes: String?
    let dueDate: Date?
    let dueTime: String?
    let priority: String?
    let reply: String?
    let error: String?

    static func from(_ response: ChatResponse) -> RecognitionResult {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            if let d = formatter.date(from: s) { return d }
            let f2 = DateFormatter()
            f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f2.date(from: s)
        }

        return RecognitionResult(
            eventType: EventType(rawValue: response.eventType ?? ""),
            title: response.title,
            startTime: parseDate(response.startTime),
            endTime: parseDate(response.endTime),
            needsDuration: response.needsDuration ?? false,
            location: response.location,
            notes: response.notes,
            dueDate: parseDate(response.dueDate),
            dueTime: response.dueTime,
            priority: response.priority,
            reply: response.reply,
            error: response.error
        )
    }
}
