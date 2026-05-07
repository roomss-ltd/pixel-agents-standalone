import Foundation

enum ToolStatusFormatter {
    static let truncateLength = 50

    static func format(toolName: String, input: [String: Any]) -> String {
        let basename: (Any?) -> String = { p in
            guard let s = p as? String else { return "" }
            return (s as NSString).lastPathComponent
        }

        switch toolName {
        case "Read":
            return "Reading \(basename(input["file_path"]))"
        case "Edit":
            return "Editing \(basename(input["file_path"]))"
        case "Write":
            return "Writing \(basename(input["file_path"]))"
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            let body = cmd.count > truncateLength
                ? String(cmd.prefix(truncateLength)) + "\u{2026}"
                : cmd
            return "Running: \(body)"
        case "Glob":         return "Searching files"
        case "Grep":         return "Searching code"
        case "WebFetch":     return "Fetching web content"
        case "WebSearch":    return "Searching the web"
        case "Task", "Agent":
            let desc = (input["description"] as? String) ?? ""
            if desc.isEmpty { return "Running subtask" }
            let body = desc.count > truncateLength
                ? String(desc.prefix(truncateLength)) + "\u{2026}"
                : desc
            return "Subtask: \(body)"
        case "AskUserQuestion": return "Waiting for your answer"
        case "EnterPlanMode":   return "Planning"
        case "NotebookEdit":    return "Editing notebook"
        default:                return "Using \(toolName)"
        }
    }
}
