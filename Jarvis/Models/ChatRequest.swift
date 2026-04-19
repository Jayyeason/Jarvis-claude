import Foundation

struct ChatRequest: Codable {
    let message: String
    let image: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case message, image
        case sessionId = "session_id"
    }
}
