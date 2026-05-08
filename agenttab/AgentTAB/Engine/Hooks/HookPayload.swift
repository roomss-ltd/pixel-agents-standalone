import Foundation

struct HookPayload: Codable, Equatable {
    let paneId: Int?
    let sessionId: String
    let hookEvent: String
    let toolName: String?
    let termProgram: String?

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case sessionId = "session_id"
        case hookEvent = "hook_event"
        case toolName = "tool_name"
        case termProgram = "term_program"
    }
}
