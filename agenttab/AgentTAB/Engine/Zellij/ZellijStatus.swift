// agenttab/AgentTAB/Engine/Zellij/ZellijStatus.swift
import Foundation

struct ZellijStatusFile: Codable {
    let sessions: [ZellijSession]
    let counts: ZellijCounts
    let updatedAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case sessions, counts
        case updatedAt = "updated_at"
    }
}

struct ZellijSession: Codable {
    let paneId: Int
    let runId: String?
    let tabNum: Int
    let tabName: String
    let icon: String
    let detail: String?
    let activity: String        // "Init", "Thinking", "Tool", "Waiting", "Done", "Idle"
    /// Agent working directory, forwarded from the Claude/Codex hook's
    /// `cwd`. Nil for older plugin builds that didn't write it.
    let cwd: String?
    /// Monotonic count of sub-agents that have finished for this session. Nil
    /// for older plugin builds; an increase signals a sub-agent completion the
    /// dock flicks a spent casing for (no state change — not a finish).
    let subagentDoneSeq: Int?

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case runId = "run_id"
        case tabNum = "tab_num"
        case tabName = "tab_name"
        case icon, detail, activity, cwd
        case subagentDoneSeq = "subagent_done_seq"
    }
}

struct ZellijCounts: Codable {
    let active: Int
    let waiting: Int
    let done: Int
}
