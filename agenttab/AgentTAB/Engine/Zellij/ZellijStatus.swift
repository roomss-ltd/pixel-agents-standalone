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

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case runId = "run_id"
        case tabNum = "tab_num"
        case tabName = "tab_name"
        case icon, detail, activity, cwd
    }
}

struct ZellijCounts: Codable {
    let active: Int
    let waiting: Int
    let done: Int
}
