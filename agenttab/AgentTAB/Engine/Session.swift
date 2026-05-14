import Foundation

struct Session: Identifiable, Equatable {
    let id: UUID
    /// Mutable so a Zellij-discovered session (initially keyed by
    /// `zellij-pane-N`) can swap in a real `run_id` once the agent emits
    /// one — keeps hooks, JSONL and zellij looking up the same Session.
    var claudeSessionId: String
    let projectName: String
    let projectPath: String
    var activity: Activity
    var currentTool: String?              // human-readable, e.g. "Editing foo.swift"
    var activeToolIds: Set<String>
    var activeToolNames: [String: String]    // toolId -> toolName
    var subagentTools: [String: Set<String>]
    var lastUpdate: Date
    var terminalKind: TerminalKind
    /// True when this session was surfaced from a stale jsonl file at
    /// startup (not actively producing output in this run). Historical
    /// sessions appear in the OLDER list but must NOT be counted in the
    /// green "done" badge — that badge tracks completions that happened
    /// while AgentTAB was running.
    var isHistorical: Bool
    /// User-assigned priority (Jira / Linear style). Persisted by the
    /// engine, keyed by `claudeSessionId`, so it survives restarts.
    /// An `.urgent` session never ages out of RECENTLY ACTIVE.
    var priority: Priority

    init(claudeSessionId: String, projectName: String, projectPath: String) {
        self.id = UUID()
        self.claudeSessionId = claudeSessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.activity = .idle
        self.currentTool = nil
        self.activeToolIds = []
        self.activeToolNames = [:]
        self.subagentTools = [:]
        self.lastUpdate = Date()
        self.terminalKind = .generic(nil)
        self.isHistorical = false
        self.priority = .default
    }
}

enum TerminalKind: Equatable {
    case generic(String?)              // optional term_program string
    case zellij(ZellijInfo)
}

struct ZellijInfo: Equatable {
    let paneId: Int
    let tabIndex: Int
    let tabName: String
    let zellijSession: String
}
