import Foundation

enum TranscriptEvent: Equatable {
    case toolStarted(toolId: String, status: String)
    case toolCompleted(toolId: String)
    case turnEnded
    case subagentToolStarted(parentId: String, toolId: String, status: String)
    case subagentToolCompleted(parentId: String, toolId: String)
}

struct TranscriptParser {
    func parseLine(_ line: String, session: inout Session) -> [TranscriptEvent] {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        let recordType = json["type"] as? String ?? ""

        switch recordType {
        case "assistant":
            return handleAssistant(json: json, session: &session)
        case "user":
            return handleUser(json: json, session: &session)
        case "system":
            return handleSystem(json: json, session: &session)
        case "progress":
            return handleProgress(json: json, session: &session)
        default:
            return []
        }
    }

    private func handleAssistant(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return [] }

        var events: [TranscriptEvent] = []
        for block in content where block["type"] as? String == "tool_use" {
            guard let toolId = block["id"] as? String,
                  let toolName = block["name"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            let status = ToolStatusFormatter.format(toolName: toolName, input: input)

            session.activeToolIds.insert(toolId)
            session.activity = .tool(toolName)
            session.currentTool = status
            session.lastUpdate = Date()
            events.append(.toolStarted(toolId: toolId, status: status))
        }
        return events
    }

    private func handleUser(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        guard let message = json["message"] as? [String: Any] else { return [] }

        if let content = message["content"] as? [[String: Any]] {
            var events: [TranscriptEvent] = []
            for block in content where block["type"] as? String == "tool_result" {
                guard let toolId = block["tool_use_id"] as? String else { continue }
                session.activeToolIds.remove(toolId)
                session.lastUpdate = Date()
                events.append(.toolCompleted(toolId: toolId))
            }
            return events
        }
        return []
    }

    private func handleSystem(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        guard json["subtype"] as? String == "turn_duration" else { return [] }
        session.activeToolIds.removeAll()
        session.subagentTools.removeAll()
        session.activity = .waiting
        session.currentTool = nil
        session.lastUpdate = Date()
        return [.turnEnded]
    }

    // Stub for future task (2.6) — return [] for now.
    private func handleProgress(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        return []
    }
}
