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
        return parseLineWithToolNames(line, session: &session, parentNames: [:])
    }

    func parseLineWithToolNames(
        _ line: String,
        session: inout Session,
        parentNames: [String: String]
    ) -> [TranscriptEvent] {
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
            return handleProgress(json: json, session: &session, parentNames: parentNames)
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
            session.activeToolNames[toolId] = toolName
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
                session.activeToolNames.removeValue(forKey: toolId)
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
        session.activeToolNames.removeAll()
        session.subagentTools.removeAll()
        // The assistant's turn ended without an explicit permission request,
        // so the session is `.done` — NOT `.waiting`. `.waiting` is reserved
        // for the explicit `PermissionRequest` hook (the user's spec: an
        // option-A/B/C prompt that needs ENTER to proceed).
        session.activity = .done
        session.currentTool = nil
        session.lastUpdate = Date()
        return [.turnEnded]
    }

    private func handleProgress(
        json: [String: Any],
        session: inout Session,
        parentNames: [String: String]
    ) -> [TranscriptEvent] {
        guard let parentToolId = json["parentToolUseID"] as? String,
              let data = json["data"] as? [String: Any] else {
            return []
        }

        let dataType = data["type"] as? String

        // bash_progress / mcp_progress: tool is actively running. The permission-timer
        // side effect from the TS implementation lives in the engine layer, not the parser.
        if dataType == "bash_progress" || dataType == "mcp_progress" {
            return []
        }

        // For other progress types, parent must be Task or Agent.
        let parentName = parentNames[parentToolId]
        guard parentName == "Task" || parentName == "Agent" else { return [] }

        guard let msg = data["message"] as? [String: Any] else { return [] }
        let msgType = msg["type"] as? String ?? ""

        guard let innerMsg = msg["message"] as? [String: Any],
              let content = innerMsg["content"] as? [[String: Any]] else { return [] }

        var events: [TranscriptEvent] = []

        if msgType == "assistant" {
            for block in content where block["type"] as? String == "tool_use" {
                guard let toolId = block["id"] as? String,
                      let toolName = block["name"] as? String else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                let status = ToolStatusFormatter.format(toolName: toolName, input: input)

                session.subagentTools[parentToolId, default: []].insert(toolId)
                session.lastUpdate = Date()
                events.append(.subagentToolStarted(parentId: parentToolId, toolId: toolId, status: status))
            }
        } else if msgType == "user" {
            for block in content where block["type"] as? String == "tool_result" {
                guard let toolId = block["tool_use_id"] as? String else { continue }
                session.subagentTools[parentToolId]?.remove(toolId)
                session.lastUpdate = Date()
                events.append(.subagentToolCompleted(parentId: parentToolId, toolId: toolId))
            }
        }

        return events
    }
}
