import Foundation

struct ChatRequest: Codable {
    let message: String
    let image: String?
    let inputMode: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case message, image
        case inputMode = "input_mode"
        case sessionId = "session_id"
    }
}
