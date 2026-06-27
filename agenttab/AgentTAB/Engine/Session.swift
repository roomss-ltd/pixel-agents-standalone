import Foundation

struct Session: Identifiable, Equatable {
    let id: UUID
    /// Mutable so a Zellij-discovered session (initially keyed by
    /// `zellij-pane-N`) can swap in a real `run_id` once the agent emits
    /// one — keeps hooks, JSONL and zellij looking up the same Session.
    var claudeSessionId: String
    let projectName: String
    /// Filesystem path of the agent's worktree. Mutable because a
    /// Zellij session learns its path lazily from the plugin's `cwd`
    /// field (it isn't known when the session is first created from a
    /// bare pane id).
    var projectPath: String
    var activity: Activity
    var currentTool: String?              // human-readable, e.g. "Editing foo.swift"
    var activeToolIds: Set<String>
    var activeToolNames: [String: String]    // toolId -> toolName
    var subagentTools: [String: Set<String>]
    /// Number of outstanding sub-agents (spawned via the `Agent`/`Task` tool).
    /// Opened by `PreToolUse(Agent)` and closed by `SubagentStop` — NOT by the
    /// Agent tool's `PostToolUse`, which can resolve before the sub-agent's work
    /// actually ends. While > 0 the main agent is delegating, so its sub-agents'
    /// own tool hooks — which arrive with the SAME `session_id`/pane and no
    /// distinguishing flag — are coalesced instead of churning this session's
    /// activity. Reset to 0 on a new prompt / hard interrupt.
    var delegatingDepth: Int
    /// True when the main agent's turn ended (`Stop`) while sub-agents were
    /// still outstanding. The session is NOT marked done yet — it holds
    /// "delegating" until the last `SubagentStop` (or the watchdog) fires the
    /// single completion. This is what keeps the orchestrator's square lit while
    /// its background sub-agents finish the work.
    var awaitingSubagentsAfterStop: Bool
    /// Last `subagent_done_seq` we've seen for this session from the Zellij
    /// status file. When the plugin's counter advances past this, a sub-agent
    /// just finished — the dock plays a "spent casing" flick (no toast, no
    /// sound). Baseline-set on discovery so we don't flick for history.
    var lastSubagentDoneSeq: Int
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
        self.delegatingDepth = 0
        self.awaitingSubagentsAfterStop = false
        self.lastSubagentDoneSeq = 0
        self.lastUpdate = Date()
        self.terminalKind = .generic(nil)
        self.isHistorical = false
        self.priority = .default
    }
}

extension Session {
    /// How many subagents (spawned via the Task / Agent tool) are
    /// currently running tools. Each parent tool id in `subagentTools`
    /// is one subagent invocation; it counts as "active" while it has
    /// any in-flight tool call. Zero for sessions that have no
    /// subagent activity (the common case).
    var activeSubagentCount: Int {
        subagentTools.values.filter { !$0.isEmpty }.count
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
