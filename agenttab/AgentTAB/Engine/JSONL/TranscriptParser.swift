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

        // Timestamp the record carries, not the wall clock. The watcher reads
        // a file from byte 0 the first time it sees it, so at launch we replay
        // transcripts that may be many minutes old — stamping `Date()` there
        // would make every replayed session look like it is happening right
        // now, which both back-dates nothing into the finished buckets and
        // fires toasts for work that ended long ago.
        let stamp = Self.recordTimestamp(json) ?? Date()

        switch recordType {
        case "assistant":
            markAgentAlive(&session, at: stamp)
            return handleAssistant(json: json, session: &session, at: stamp)
        case "user":
            markAgentAlive(&session, at: stamp)
            return handleUser(json: json, session: &session, at: stamp)
        case "system":
            markAgentAlive(&session, at: stamp)
            return handleSystem(json: json, session: &session, at: stamp)
        case "progress":
            markAgentAlive(&session, at: stamp)
            return handleProgress(json: json, session: &session, parentNames: parentNames, at: stamp)
        default:
            return []
        }
    }

    /// A record in the transcript was written by the agent itself, so it is
    /// hard proof the agent was alive at `stamp`. Never moves backwards — a
    /// re-scan of already-parsed bytes must not un-prove liveness.
    private func markAgentAlive(_ session: inout Session, at stamp: Date) {
        session.lastEvidence = max(session.lastEvidence ?? .distantPast, stamp)
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Claude writes `"timestamp":"2026-07-14T16:08:32.123Z"` on every
    /// assistant / user / system / progress record. Older transcripts (and
    /// the fixtures in our tests) omit it — callers fall back to `Date()`.
    static func recordTimestamp(_ json: [String: Any]) -> Date? {
        guard let raw = json["timestamp"] as? String else { return nil }
        return iso8601WithFraction.date(from: raw) ?? iso8601Plain.date(from: raw)
    }

    private func handleAssistant(json: [String: Any], session: inout Session, at stamp: Date) -> [TranscriptEvent] {
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
            session.lastUpdate = stamp
            events.append(.toolStarted(toolId: toolId, status: status))
        }
        return events
    }

    private func handleUser(json: [String: Any], session: inout Session, at stamp: Date) -> [TranscriptEvent] {
        guard let message = json["message"] as? [String: Any] else { return [] }

        if let content = message["content"] as? [[String: Any]] {
            var events: [TranscriptEvent] = []
            for block in content where block["type"] as? String == "tool_result" {
                guard let toolId = block["tool_use_id"] as? String else { continue }
                session.activeToolIds.remove(toolId)
                session.activeToolNames.removeValue(forKey: toolId)
                session.lastUpdate = stamp
                events.append(.toolCompleted(toolId: toolId))
            }

            // The last in-flight tool came back, so the agent is thinking
            // again — not still running a tool. Without this, `.tool` is a
            // one-way door: the only other state the transcript can produce
            // is the `turn_duration` system record, which most transcripts
            // never contain, so a session that finished normally would sit
            // at `.tool(lastTool)` — reading as "processing" — forever.
            if !events.isEmpty, session.activeToolIds.isEmpty, case .tool = session.activity {
                session.activity = .thinking
                session.currentTool = nil
            }
            return events
        }
        return []
    }

    private func handleSystem(json: [String: Any], session: inout Session, at stamp: Date) -> [TranscriptEvent] {
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
        session.lastUpdate = stamp
        return [.turnEnded]
    }

    private func handleProgress(
        json: [String: Any],
        session: inout Session,
        parentNames: [String: String],
        at stamp: Date
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
                session.lastUpdate = stamp
                events.append(.subagentToolStarted(parentId: parentToolId, toolId: toolId, status: status))
            }
        } else if msgType == "user" {
            for block in content where block["type"] as? String == "tool_result" {
                guard let toolId = block["tool_use_id"] as? String else { continue }
                session.subagentTools[parentToolId]?.remove(toolId)
                session.lastUpdate = stamp
                events.append(.subagentToolCompleted(parentId: parentToolId, toolId: toolId))
            }
        }

        return events
    }
}
