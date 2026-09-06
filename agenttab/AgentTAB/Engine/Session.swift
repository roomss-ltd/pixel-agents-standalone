import Foundation

enum AgentKind: String, Codable, Equatable {
    case claude
    case codex
    case devin
    case unknown

    init(statusValue: String?) {
        self = statusValue.flatMap(Self.init(rawValue:)) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .devin: return "Devin"
        case .unknown: return "Agent"
        }
    }
}

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
    /// Active descendants reported by a provider's native session store.
    /// Claude descendants are already represented by `subagentTools`.
    var nativeSubagentCount: Int
    var agentKind: AgentKind
    var providerSessionTitle: String?
    var lastUpdate: Date
    /// Last moment we had *proof* the agent was alive: a hook event it fired,
    /// or a line it appended to its own transcript. Nil until such proof
    /// arrives.
    ///
    /// Distinct from `lastUpdate`, which is a display anchor that also moves
    /// on second-hand reports. The Zellij plugin re-publishes every pane's
    /// activity every 5s whether or not the agent behind it still exists, so
    /// "Zellij says Tool" is not evidence of life — only agent-authored
    /// writes are. The staleness sweep keys on this field.
    var lastEvidence: Date?
    /// When the agent's current run began, recovered from the Zellij plugin's
    /// `run_id`. The plugin mints a fresh run id on every `UserPromptSubmit`,
    /// so this is the moment the turn now being reported started — which puts
    /// a ceiling on how long that turn can plausibly still be running.
    var runStartedAt: Date?
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

    init(
        claudeSessionId: String,
        projectName: String,
        projectPath: String,
        agentKind: AgentKind = .claude
    ) {
        self.id = UUID()
        self.claudeSessionId = claudeSessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.activity = .idle
        self.currentTool = nil
        self.activeToolIds = []
        self.activeToolNames = [:]
        self.subagentTools = [:]
        self.nativeSubagentCount = 0
        self.agentKind = agentKind
        self.providerSessionTitle = nil
        self.lastUpdate = Date()
        self.lastEvidence = nil
        self.runStartedAt = nil
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
        subagentTools.values.filter { !$0.isEmpty }.count + nativeSubagentCount
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
