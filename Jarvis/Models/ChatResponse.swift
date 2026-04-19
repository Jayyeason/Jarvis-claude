import Foundation

struct ChatResponse: Codable {
    var eventType: String?
    var title: String?
    var startTime: String?
    var endTime: String?
    var needsDuration: Bool?
    var location: String?
    var notes: String?
    var dueDate: String?
    var dueTime: String?
    var priority: String?
    var reply: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case needsDuration = "needs_duration"
        case location, notes
        case dueDate = "due_date"
        case dueTime = "due_time"
        case priority, reply, error
    }
}
