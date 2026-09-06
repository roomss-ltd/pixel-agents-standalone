import Foundation
import Combine
import SwiftUI

/// Zellij pane ids are only unique inside one Zellij session. Two live
/// sessions routinely both contain pane 1, so every pane-owned cache must use
/// the session name as part of its key.
private struct ZellijPaneKey: Hashable {
    let sessionName: String
    let paneId: Int

    init(sessionName: String, paneId: Int) {
        self.sessionName = sessionName
        self.paneId = paneId
    }

    init(_ info: ZellijInfo) {
        self.init(sessionName: info.zellijSession, paneId: info.paneId)
    }
}

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    /// True once the Zellij plugin has been detected on the system. While
    /// active, the UI only counts/shows sessions matched to a real Zellij
    /// pane — historical jsonl files that don't correspond to a live tab
    /// are hidden so the OLDER list mirrors what Hammerspoon would show.
    @Published private(set) var zellijDetected: Bool = false

    /// User-dismissed Zellij panes. The unlink button in the expanded
    /// panel adds a pane key here; the session is then filtered out of
    /// `displaySessions` until the user reopens it manually.
    @Published private var deniedPanes: Set<ZellijPaneKey> = []

    /// Hide a session from the panel. Currently only Zellij sessions are
    /// dismissible — for non-Zellij the unlink button is a no-op.
    func hide(_ session: Session) {
        if case .zellij(let info) = session.terminalKind {
            deniedPanes.insert(ZellijPaneKey(info))
        }
    }

    /// View-facing session list. When the Zellij plugin is active, trust its
    /// view of the world and only surface Zellij-tagged sessions. A valid empty
    /// snapshot means there are no live agents; falling back to JSONL history
    /// here floods a freshly restarted session with unrelated old agents.
    var displaySessions: [Session] {
        let denied = deniedPanes
        let withoutDenied = sessions.filter { s -> Bool in
            if case .zellij(let info) = s.terminalKind {
                return !denied.contains(ZellijPaneKey(info))
            }
            return true
        }
        guard zellijDetected else { return withoutDenied }
        let zellijOnly = withoutDenied.filter {
            if case .zellij = $0.terminalKind { return true } else { return false }
        }
        return zellijOnly
    }

    /// Chip label for a session — mirrors the Hammerspoon webview's
    /// `_display_num` rule: a Zellij tab is shown as its `tab_num` (e.g.
    /// `"3"`); when multiple panes share a tab number, suffix them with a
    /// disambiguator in pane-id order (`"3.1"`, `"3.2"`, …). Non-Zellij
    /// sessions fall back to the last two characters of the Claude
    /// session id.
    func displayLabel(for session: Session) -> String {
        switch session.terminalKind {
        case .zellij(let info):
            // Peers are panes sharing a tab *within the same Zellij session*.
            // Tab numbers are per-session, so two Zellij sessions both have a
            // tab 2 — grouping on `tabIndex` alone makes them look like two
            // panes of one tab and labels them "2.1" / "2.2". Worse, the peer
            // set changes as rows come and go, so a stable tab visibly flips
            // between "2" and "2.1".
            let peers = displaySessions
                .compactMap { s -> ZellijInfo? in
                    if case .zellij(let i) = s.terminalKind,
                       i.tabIndex == info.tabIndex,
                       i.zellijSession == info.zellijSession {
                        return i
                    }
                    return nil
                }
                .sorted { $0.paneId < $1.paneId }
            if peers.count > 1,
               let order = peers.firstIndex(where: { $0.paneId == info.paneId }) {
                return "\(info.tabIndex).\(order + 1)"
            }
            return "\(info.tabIndex)"
        case .generic:
            return String(session.claudeSessionId.suffix(2))
        }
    }

    /// Row title — prefers the Zellij `tab_name` (so an agent renamed to
    /// `mitar-booking` shows that, not the project hash). Falls back to
    /// the JSONL-derived project name.
    func displayName(for session: Session) -> String {
        if case .zellij(let info) = session.terminalKind, !info.tabName.isEmpty {
            return info.tabName
        }
        return session.projectName
    }

    /// Resolved filesystem path for the agent's worktree, or nil when
    /// the session is Zellij-only and was never matched to a JSONL
    /// session (no path was ever discovered).
    func worktreePath(for session: Session) -> String? {
        guard !session.projectPath.isEmpty else { return nil }
        return session.projectPath
    }

    /// Open the worktree folder in Finder. No-op if we don't have a
    /// resolved path.
    func openFolder(_ session: Session) {
        guard let path = worktreePath(for: session) else {
            AgentLog.engine.info("openFolder skipped: no path for session=\(session.claudeSessionId, privacy: .public)")
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        AgentLog.engine.info("openFolder \(path, privacy: .public)")
    }

    /// Cursor first, VS Code second. We pick whichever is installed; if
    /// neither is found we fall back to Finder so the click isn't a
    /// dead-end. Bundle id list covers both Cursor's older (ToDesktop)
    /// and newer (com.cursor.Cursor) packaging.
    private static let editorBundleIds: [String] = [
        "com.todesktop.230313mzl4w4u92",   // Cursor (ToDesktop build)
        "com.cursor.Cursor",                // Cursor (newer)
        "com.microsoft.VSCode",             // Visual Studio Code
        "com.visualstudio.code.oss",        // VSCodium
    ]

    func openEditor(_ session: Session) {
        guard let path = worktreePath(for: session) else {
            AgentLog.engine.info("openEditor skipped: no path for session=\(session.claudeSessionId, privacy: .public)")
            return
        }
        let url = URL(fileURLWithPath: path)
        let ws = NSWorkspace.shared

        for bundleId in Self.editorBundleIds {
            guard let appURL = ws.urlForApplication(withBundleIdentifier: bundleId) else { continue }
            let config = NSWorkspace.OpenConfiguration()
            ws.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if let error {
                    AgentLog.engine.error("openEditor failed bundle=\(bundleId, privacy: .public) error=\(String(describing: error), privacy: .public)")
                } else {
                    AgentLog.engine.info("openEditor \(bundleId, privacy: .public) \(path, privacy: .public)")
                }
            }
            return
        }
        // Neither editor present — fall back to Finder so the click
        // still does something.
        AgentLog.engine.info("openEditor fallback to Finder (no Cursor/VSCode installed)")
        openFolder(session)
    }

    /// Bring whichever terminal is hosting zellij to the foreground and
    /// focus the right tab. Used by the expanded panel's agent-row click
    /// and by toast notifications (tap to jump to that agent).
    func focus(_ session: Session) {
        switch session.terminalKind {
        case .zellij(let info):
            guard let zellijPath = ZellijStatusReader.zellijExecutableURL?.path else {
                AgentLog.engine.error("zellij focus skipped: no safe client executable")
                return
            }
            Task { [weak self] in
                let clientCount = await Task.detached {
                    Self.connectedClientCount(
                        session: info.zellijSession,
                        zellijPath: zellijPath
                    )
                }.value
                guard let self else { return }
                if clientCount == 0 {
                    self.reattachInGhostty(info, zellijPath: zellijPath)
                } else {
                    self.focusAttachedZellij(info, zellijPath: zellijPath)
                }
            }
        case .generic:
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: session.projectPath)]
            )
        }
    }

    private func focusAttachedZellij(_ info: ZellijInfo, zellijPath: String) {
        // 1. Bring the terminal app forward FIRST so the user sees
        //    the tab swap happen, not just a flash later. Activating
        //    after firing the zellij command races with zellij's
        //    own redraw and is the most common reason the toast
        //    redirect "sometimes" doesn't seem to do anything.
        let knownTerminals: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "com.zeit.hyper",
            "co.zeit.hyper",
            "dev.zed.Zed",
        ]
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier,
               knownTerminals.contains(bundleId) {
                app.activate(options: [.activateIgnoringOtherApps])
                break
            }
        }

        // 2. Use the same patched binary that owns the live session.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: zellijPath)
        task.arguments = ["-s", info.zellijSession, "action", "go-to-tab", "\(info.tabIndex)"]
        do {
            try task.run()
        } catch {
            print("[Engine] zellij focus failed: \(error)")
        }
    }

    nonisolated static func connectedClientCount(from output: String) -> Int? {
        let lines = output.split(whereSeparator: \Character.isNewline)
        guard lines.first?.contains("CLIENT_ID") == true else { return nil }
        return max(0, lines.count - 1)
    }

    private nonisolated static func connectedClientCount(
        session: String,
        zellijPath: String
    ) -> Int? {
        guard !session.isEmpty else { return nil }

        let output = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: zellijPath)
        task.arguments = ["-s", session, "action", "list-clients"]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            AgentLog.engine.error("zellij client check failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return connectedClientCount(from: text)
    }

    private func reattachInGhostty(_ info: ZellijInfo, zellijPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [
            "-na", "Ghostty.app", "--args", "-e",
            zellijPath, "attach", info.zellijSession,
        ]
        do {
            try task.run()
            AgentLog.engine.info("reattaching detached zellij session=\(info.zellijSession, privacy: .public)")
        } catch {
            AgentLog.engine.error("zellij reattach failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Mirrors the Hammerspoon webview's `RECENT_FINISHED_WINDOW_SECONDS`
    /// — anything finished within this many seconds counts as
    /// "recently active"; anything older falls into "OLDER FINISHED" and
    /// is excluded from the green badge.
    static let recentFinishedWindow: TimeInterval = 3 * 3600   // 3 hours

    /// Tab-index sort key — ascending zellij `tab_num`, then session name and
    /// `paneId` to keep collisions stable. Non-zellij sessions sort to the end.
    static func byTabIndexAsc(_ a: Session, _ b: Session) -> Bool {
        let ai = tabIndex(of: a)
        let bi = tabIndex(of: b)
        if ai.tab != bi.tab { return ai.tab < bi.tab }
        if ai.session != bi.session { return ai.session < bi.session }
        return ai.pane < bi.pane
    }

    private static func tabIndex(of s: Session) -> (tab: Int, session: String, pane: Int) {
        if case .zellij(let info) = s.terminalKind {
            return (info.tabIndex, info.zellijSession, info.paneId)
        }
        return (Int.max, "", Int.max)
    }

    private var sessionsByJsonlURL: [URL: UUID] = [:]
    private var sessionsByClaudeId: [String: UUID] = [:]
    /// A pane id is scoped to its Zellij session. Keeping the full key here
    /// prevents two live sessions' pane 1 from overwriting the same row.
    private var sessionsByZellijPane: [ZellijPaneKey: UUID] = [:]

    /// The Claude session id buried in a Zellij `run_id`.
    ///
    /// The plugin mints run ids as `"{session_id}:{pane_id}:{unix}:{seq}"`
    /// (see `next_run_id` in claude-tab-status/src/event_handler.rs), so only
    /// the leading component is the id that the JSONL filename and the hook
    /// payload's `session_id` both use. Treating the whole composite as the
    /// session id means `sessionsByClaudeId[runId]` can never match a
    /// JSONL-discovered session: the agent ends up with TWO Session rows, and
    /// hook events resolve to the JSONL one — which `displaySessions` hides
    /// whenever Zellij is active. Every real-time signal we have (permission
    /// requests, Stop) would land on a row nobody can see.
    nonisolated static func claudeSessionId(fromRunId runId: String) -> String? {
        let head = runId.prefix { $0 != ":" }
        return head.isEmpty ? nil : String(head)
    }

    /// When the run began, from the third component of the plugin's `run_id`.
    /// A fresh id is minted on every `UserPromptSubmit`, so this is the start
    /// of the turn the pane is currently reporting.
    nonisolated static func runStart(fromRunId runId: String) -> Date? {
        let parts = runId.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, let unix = TimeInterval(parts[2]), unix > 0 else { return nil }
        return Date(timeIntervalSince1970: unix)
    }

    // MARK: - Notification gates (Phase 0)

    /// Identifies what triggered a state-change consideration. Used to
    /// gate notifications on whether the underlying source actually
    /// advanced — re-running the engine over an unchanged source must
    /// never produce a toast.
    enum NotificationSource {
        case jsonl(URL)
        case zellij(paneId: Int, updatedAt: Date?)
        case hook
    }

    /// Most recent source timestamp seen per session. JSONL: the highest
    /// `Date()` we stamped from a parsed line. Zellij: the plugin's
    /// `updated_at`. Hook: always advances (real-time, monotonic).
    private var lastSourceTimestamp: [UUID: Date] = [:]

    /// Which kind of toast a notification produces. Used as part of the
    /// throttle key so a "waiting" toast doesn't eat the budget of a
    /// subsequent "done" toast (the most common reason a finish-toast
    /// silently went missing — agent asked for approval, ran, finished,
    /// done dropped because waiting fired < 60s ago).
    private enum NotifyTarget: Hashable { case waiting, done }

    /// Per-session dedupe: identical (from, to) within 30s collapses.
    /// Cleared as soon as the session is observed leaving the cached
    /// target state — re-entry after a pass-through (waiting → tool → done,
    /// or done → thinking → done from a re-prompt) counts as fresh.
    private var lastNotifiedTransition: [UUID: (from: Activity, to: Activity, firedAt: Date)] = [:]

    /// Per-(session, target) throttle: at most one toast of a given kind
    /// per minute, but waiting and done budgets are independent.
    private var lastNotifiedAt: [UUID: [NotifyTarget: Date]] = [:]

    private static let dedupeWindow: TimeInterval = 30
    private static let throttleWindow: TimeInterval = 60

    // MARK: - Urgent-finished reminders

    /// After an `.urgent` session finishes, it gets at most
    /// `urgentReminderCap` pink reminders, all within a single
    /// `urgentReminderWindow` measured from the finish time — then it
    /// goes quiet for good (until it runs and finishes again).
    private static let urgentReminderWindow: TimeInterval = 120   // 2 min from finish
    private static let urgentReminderCap = 3

    /// How many reminders we've already fired for a given session's
    /// current finished state. Cleared the moment the session stops
    /// qualifying, so a fresh finish starts a clean count.
    private var urgentReminders: [UUID: Int] = [:]
    private var urgentReminderTimer: AnyCancellable?

    // MARK: - Priority (Jira/Linear-style tab prioritisation)

    private static let prioritiesKey = "AgentTAB.priorities"

    /// `claudeSessionId → Priority.rawValue`. Persisted so a user's
    /// prioritisation survives an AgentTAB restart.
    private var storedPriorities: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: Self.prioritiesKey) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.prioritiesKey) }
    }

    /// Priority stored for a given claude/run id, or the default when
    /// the user hasn't assigned one. Used at session-discovery time.
    func storedPriority(for claudeSessionId: String) -> Priority {
        Priority(rawValue: storedPriorities[claudeSessionId] ?? Priority.default.rawValue) ?? .default
    }

    /// Assign a priority to a session — updates the live model and
    /// persists immediately, keyed by `claudeSessionId`.
    func setPriority(_ priority: Priority, for session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].priority = priority
        var map = storedPriorities
        map[sessions[idx].claudeSessionId] = priority.rawValue
        storedPriorities = map
        AgentLog.engine.info("priority set session=\(self.sessions[idx].claudeSessionId, privacy: .public) priority=\(priority.displayName, privacy: .public)")
    }

    /// Move a stored priority across an id change. Zellij sessions
    /// start keyed by `zellij-pane-N` and later surface a real
    /// `run_id`; without this the user's assignment would be orphaned
    /// under the old key.
    private func migratePriorityKey(from oldId: String, to newId: String) {
        var map = storedPriorities
        guard let value = map.removeValue(forKey: oldId) else { return }
        map[newId] = value
        storedPriorities = map
    }
    // MARK: - Staleness sweep

    /// How long a session may sit in a transient state (`.initState`,
    /// `.thinking`, `.tool`) with nothing proving the agent is still alive
    /// before we stop calling it active.
    ///
    /// This only ever fires when a terminal signal was LOST. A normal finish
    /// sends `Stop` and flips to `.done` immediately; this is the backstop for
    /// agents that are killed, crash, or are Ctrl-C'd, which never send
    /// anything. 15 minutes clears comfortably above the longest legitimate
    /// silence — Claude's Bash tool caps at 10 minutes, and a long thinking
    /// turn writes nothing to the transcript while it streams.
    static let transientStaleTimeout: TimeInterval = 15 * 60

    /// Ceiling on how long a single agent turn can plausibly still be running.
    /// Used with `Session.runStartedAt` to convict panes whose transcript has
    /// already been rotated away, where there is no other clock to judge them by.
    static let maxPlausibleRunDuration: TimeInterval = 24 * 3600

    /// Beyond this, a state change is history, not news — no toast. Replaying
    /// a transcript at launch, or first-scanning a Zellij pane that finished
    /// hours ago, both walk a session into `.done`; without this the user gets
    /// a burst of "Finished successfully" for work that ended long before
    /// AgentTAB was even running.
    private static let staleEventCutoff: TimeInterval = 120

    private var staleSweepTimer: AnyCancellable?

    /// pane key → the activity Zellij is currently reporting, and when it first
    /// reported it. The plugin republishes every pane every 5s regardless of
    /// whether the agent behind it still exists, so a repeat of the same
    /// status is not new information — only a *change* is. Used as the
    /// evidence of last resort for panes we can't match to a transcript.
    private var zellijActivityFirstSeen: [ZellijPaneKey: (activity: Activity, at: Date)] = [:]

    private let parser = TranscriptParser()
    private let transcripts: TranscriptLocator
    private let codexSessionsDir: URL?
    private let devinDatabaseURL: URL?
    private var nativeSubagentScanInFlight = false
    private var lastNativeSubagentScan = Date.distantPast
    private let permissionTimer = PermissionTimer()
    private let jsonlWatcher: JSONLWatcher
    private var hookSocket: HookSocketListener?
    private var lastHookEvent: [String: Date] = [:]   // claudeSessionId -> when
    private var zellijReader: ZellijStatusReader?
    private let toastPanel = ToastPanel()
    private let soundPlayer = SoundPlayer()

    @AppStorage("AgentTAB.toast.corner") private var toastCornerRaw: String = ToastCorner.bottomRight.rawValue
    @AppStorage("AgentTAB.sounds.enabled") private var soundsEnabled: Bool = true

    private var toastCorner: ToastCorner {
        ToastCorner(rawValue: toastCornerRaw) ?? .bottomRight
    }

    private let zellijStatusDir: URL

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         zellijStatusDir: URL = ZellijStatusReader.defaultStatusDir,
         codexSessionsDir: URL? = nil,
         devinDatabaseURL: URL? = nil) {
        let defaultProjectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let resolvedCodexDir = codexSessionsDir ?? (
            projectsDir.standardizedFileURL == defaultProjectsDir.standardizedFileURL
                ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
                : nil
        )
        self.jsonlWatcher = JSONLWatcher(projectsDir: projectsDir)
        self.transcripts = TranscriptLocator(projectsDir: projectsDir, codexSessionsDir: resolvedCodexDir)
        self.codexSessionsDir = resolvedCodexDir
        self.devinDatabaseURL = devinDatabaseURL ?? (
            projectsDir.standardizedFileURL == defaultProjectsDir.standardizedFileURL
                ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/devin/cli/sessions.db")
                : nil
        )
        self.zellijStatusDir = zellijStatusDir
    }

    func start() {
        jsonlWatcher.onSessionDiscovered = { [weak self] url, projectHash, mtime, isLive in
            Task { @MainActor in
                self?.discoverSession(jsonlURL: url, projectHash: projectHash, mtime: mtime, isLive: isLive)
            }
        }
        jsonlWatcher.onLine = { [weak self] url, line in
            Task { @MainActor in self?.applyLine(line, jsonlURL: url) }
        }
        jsonlWatcher.start()

        if HookInstaller.hooksInstalled {
            let listener = HookSocketListener(socketPath: HookInstaller.socketPath)
            listener.onPayload = { [weak self] payload in
                Task { @MainActor in self?.applyHook(payload) }
            }
            do {
                try listener.start()
                hookSocket = listener
                print("[Engine] Hook socket listening at \(HookInstaller.socketPath)")
            } catch {
                print("[Engine] Hook socket failed to start: \(error)")
            }
        }

        let probe = EnvironmentProbe.detect(statusDir: zellijStatusDir)
        if probe.pluginState == .producingStatusFiles {
            zellijDetected = true
            zellijReader = ZellijStatusReader(statusDir: zellijStatusDir)
            zellijReader?.onUpdate = { [weak self] fileMap in
                Task { @MainActor in self?.applyZellijStatus(fileMap) }
            }
            zellijReader?.start()
            print("[Engine] Zellij status reader active")
        }

        startUrgentReminderTimer()
        startStaleSweepTimer()
    }

    // MARK: - Staleness sweep

    private func startStaleSweepTimer() {
        staleSweepTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sweepStaleSessions() }
    }

    /// Demote sessions that claim to be working but have gone silent past
    /// `transientStaleTimeout`.
    ///
    /// Every event source we have is edge-triggered and lossy: hooks stop
    /// arriving when a process is killed rather than exiting, and the Zellij
    /// plugin only decays `Done → Idle` — it never ages out `Thinking`/`Tool`,
    /// so a pane whose agent died a month ago is still published as active
    /// every 5 seconds. Without a level-triggered sweep those states are
    /// one-way doors and the notch shows work that stopped long ago.
    ///
    /// Demotion is `.idle`, never `.done`, and fires no toast: we did not
    /// observe a completion, we lost track of the agent. Saying "Finished
    /// successfully" for a session that was killed would be a lie.
    func sweepStaleSessions(now: Date = Date()) {
        refreshNativeSubagents(now: now)
        for index in sessions.indices {
            let session = sessions[index]
            guard session.activity.isTransient, !session.isHistorical else { continue }

            let evidence = lastEvidence(for: session, now: now)
            let silence = now.timeIntervalSince(evidence)
            guard silence >= Self.transientStaleTimeout else { continue }

            let oldActivity = session.activity
            sessions[index].activity = .idle
            sessions[index].currentTool = nil
            sessions[index].activeToolIds.removeAll()
            sessions[index].activeToolNames.removeAll()
            sessions[index].subagentTools.removeAll()
            // Anchor the row at the last moment the agent could be proven
            // alive, not at the moment we noticed — that way it buckets into
            // RECENTLY / OLDER FINISHED by when it actually stopped.
            sessions[index].lastUpdate = evidence
            permissionTimer.cancel(for: session.claudeSessionId)

            AgentLog.engine.info("transition watchdog session=\(session.claudeSessionId, privacy: .public) \(oldActivity.logTag, privacy: .public)→idle silent=\(Int(silence))s")
        }
    }

    private func refreshNativeSubagents(now: Date) {
        let needsCodex = sessions.contains {
            $0.agentKind == .codex
                && !$0.isHistorical
                && ($0.activity.isTransient || $0.nativeSubagentCount > 0)
        }
        // Devin's database is also its live activity source, so keep polling
        // while a Devin pane exists even when the last snapshot was idle.
        let needsDevin = sessions.contains {
            $0.agentKind == .devin && !$0.isHistorical
        }
        guard !nativeSubagentScanInFlight,
              now.timeIntervalSince(lastNativeSubagentScan) >= 15,
              needsCodex || needsDevin
        else { return }

        let codexDir = needsCodex ? codexSessionsDir : nil
        let devinDB = needsDevin ? devinDatabaseURL : nil
        nativeSubagentScanInFlight = true
        lastNativeSubagentScan = now
        Task { [weak self] in
            let counts = await Task.detached(priority: .utility) {
                let codexCounts = codexDir.map {
                    CodexSubagentScanner.activeCounts(sessionsDir: $0, now: now)
                } ?? [:]
                let devin = devinDB.map { DevinUsageReader.read(databaseURL: $0) } ?? []
                return (codexCounts, devin)
            }.value
            guard let self else { return }
            self.nativeSubagentScanInFlight = false
            for index in self.sessions.indices where self.sessions[index].agentKind == .codex {
                self.sessions[index].nativeSubagentCount = counts.0[self.sessions[index].claudeSessionId] ?? 0
            }
            let devinSessions = self.sessions.indices.filter { self.sessions[$0].agentKind == .devin }
            for index in devinSessions {
                let wanted = Self.normalizedDevinTitle(self.sessions[index].providerSessionTitle)
                let match = counts.1.first {
                    !wanted.isEmpty && Self.normalizedDevinTitle($0.title) == wanted
                } ?? (devinSessions.count == 1 ? counts.1.max { $0.lastActivityAt < $1.lastActivityAt } : nil)
                self.sessions[index].nativeSubagentCount = match?.activeSubagentCount ?? 0
                guard let match else { continue }
                if match.activeSubagentCount > 0 {
                    self.sessions[index].activity = .tool("Subagent")
                } else if match.activeToolCount > 0 {
                    self.sessions[index].activity = .tool("Working")
                } else if now.timeIntervalSince1970 - match.lastActivityAt < 30 {
                    self.sessions[index].activity = .thinking
                } else {
                    self.sessions[index].activity = .idle
                }
                self.sessions[index].lastUpdate = Date(timeIntervalSince1970: match.lastActivityAt)
                if self.sessions[index].projectPath.isEmpty {
                    self.sessions[index].projectPath = match.workingDirectory
                }
            }
        }
    }

    nonisolated private static func normalizedDevinTitle(_ title: String?) -> String {
        (title ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a claim that the agent is working isn't backed by any proof
    /// that it still exists.
    ///
    /// The Zellij plugin republishes every pane's last known activity every 5
    /// seconds for as long as the pane is open — so for a ghost it asserts
    /// "Thinking" forever. Re-asserting an unbacked claim is not new evidence,
    /// and adopting it would undo the sweep on the very next tick: the row
    /// would flip idle → tool → idle → tool every 5 seconds instead of
    /// settling. Both the sweep and the apply path have to ask this same
    /// question, or they fight each other.
    private func isUnbackedClaim(_ activity: Activity, for session: Session, now: Date) -> Bool {
        guard activity.isTransient else { return false }

        if now.timeIntervalSince(lastEvidence(for: session, now: now)) >= Self.transientStaleTimeout {
            return true
        }

        // No proof of life has EVER reached us for this session — nothing on the
        // hook socket, and no transcript anywhere on disk (Claude rotates those
        // away once a session is long dead) — and the turn it claims to still be
        // running was started more than a day ago. Nothing runs for a day.
        //
        // This is what convicts the oldest ghosts on sight. Without it they'd
        // have to serve out the full silence window on every app launch, because
        // the only clock available for a pane with no transcript starts when
        // AgentTAB first meets it — so restarting the app would hand each corpse
        // a fresh 15 minutes of looking busy.
        //
        // A fresh run id keeps a newly seen pane trustworthy until its own
        // transcript appears. The age ceiling still catches old bridge files
        // whose provider transcript has already been removed.
        if session.lastEvidence == nil,
           let started = session.runStartedAt,
           now.timeIntervalSince(started) >= Self.maxPlausibleRunDuration,
           transcripts.lastWrite(forSessionId: session.claudeSessionId, now: now) == nil {
            return true
        }

        return false
    }

    /// The most recent moment we can *prove* this agent was alive.
    ///
    /// Only agent-authored writes count as proof: hook events it fired, lines
    /// it appended to its transcript. A Zellij status file republishing the
    /// same activity every 5s proves nothing — that is exactly how a dead pane
    /// masquerades as a live one.
    private func lastEvidence(for session: Session, now: Date) -> Date {
        var proof = session.lastEvidence

        // The transcript's mtime is the strongest signal available, and the
        // only one that survives an AgentTAB restart: Claude appends to it as
        // it works, so its age is the agent's silence.
        if let write = transcripts.lastWrite(forSessionId: session.claudeSessionId, now: now) {
            proof = max(proof ?? .distantPast, write)
        }
        if let proof { return proof }

        // Nothing agent-authored to go on — a Zellij pane we've never matched
        // to a transcript. Fall back to when it first reported the activity
        // it's currently reporting; a repeat is not new information.
        if case .zellij(let info) = session.terminalKind,
           let seen = zellijActivityFirstSeen[ZellijPaneKey(info)],
           seen.activity == session.activity {
            return seen.at
        }
        return session.lastUpdate
    }

    // MARK: - Session removal

    /// Drop a session and every index that points at it.
    ///
    /// Leaving a `sessionsByJsonlURL` entry aimed at a removed UUID silently
    /// black-holes that file: `applyLine` resolves the dead id, bails, and the
    /// watcher never re-announces the file because it still holds a source for
    /// it — so the session can never come back. Releasing the file in the
    /// watcher lets a live transcript re-register itself on the next scan.
    private func removeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        sessions.remove(at: index)

        if case .zellij(let info) = session.terminalKind {
            let paneKey = ZellijPaneKey(info)
            sessionsByZellijPane.removeValue(forKey: paneKey)
            zellijActivityFirstSeen.removeValue(forKey: paneKey)
            warnedElapsedParseFailure.remove(paneKey)
        }
        for (url, owner) in sessionsByJsonlURL where owner == id {
            sessionsByJsonlURL.removeValue(forKey: url)
            jsonlWatcher.release(fileURL: url)
        }
        let removedClaudeKeys = sessionsByClaudeId.compactMap { key, owner in owner == id ? key : nil }
        for key in removedClaudeKeys {
            sessionsByClaudeId.removeValue(forKey: key)
            if let replacement = sessions.first(where: { $0.claudeSessionId == key }) {
                sessionsByClaudeId[key] = replacement.id
            }
        }
        lastSourceTimestamp.removeValue(forKey: id)
        lastNotifiedTransition.removeValue(forKey: id)
        lastNotifiedAt.removeValue(forKey: id)
        urgentReminders.removeValue(forKey: id)
        lastHookEvent.removeValue(forKey: session.claudeSessionId)
        permissionTimer.cancel(for: session.claudeSessionId)
    }

    // MARK: - Urgent-finished reminder loop

    private func startUrgentReminderTimer() {
        // 30s tick: with a 3-per-2-min cap that produces ~3 reminders
        // spread across each rolling 2-minute window.
        urgentReminderTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkUrgentReminders() }
    }

    /// Fire a pink reminder for `.urgent` sessions that have finished —
    /// at most `urgentReminderCap` times, all inside a single
    /// `urgentReminderWindow` measured from the finish time. Once the
    /// cap is hit, or the window from the finish has elapsed, the
    /// session goes quiet for good (until it runs and finishes again).
    private func checkUrgentReminders() {
        let now = Date()

        let qualifying = sessions.filter { s -> Bool in
            guard s.priority == .urgent, !s.isHistorical else { return false }
            switch s.activity {
            case .done, .idle: return true
            default:           return false
            }
        }

        // Drop reminder state for sessions that no longer qualify —
        // resumed processing, removed, de-prioritised. The next time
        // such a session finishes it starts a clean count, anchored to
        // its new finish time.
        let qualifyingIds = Set(qualifying.map(\.id))
        urgentReminders = urgentReminders.filter { qualifyingIds.contains($0.key) }

        for session in qualifying {
            // Window is [finishTime, finishTime + 2min]. `lastUpdate` is
            // the moment the session went done/idle and stays put while
            // it's finished, so it's the finish-time anchor.
            let windowEnd = session.lastUpdate.addingTimeInterval(Self.urgentReminderWindow)
            guard now <= windowEnd else { continue }   // window elapsed → quiet

            let count = urgentReminders[session.id] ?? 0
            guard count < Self.urgentReminderCap else { continue }   // hit the cap → quiet

            urgentReminders[session.id] = count + 1
            fireUrgentReminder(for: session)
        }
    }

    private func fireUrgentReminder(for session: Session) {
        let focusAction: () -> Void = { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .agentTabRequestPeek, object: nil)
            if let live = self.sessions.first(where: { $0.id == session.id }) {
                self.focus(live)
            } else {
                self.focus(session)
            }
        }
        let toast = Toast(
            variant: .urgentReminder,
            taskId: displayLabel(for: session),
            projectName: displayName(for: session),
            message: "Urgent · finished, still unattended"
        )
        toastPanel.show(toast, duration: 5, onTap: focusAction)
        if soundsEnabled { soundPlayer.playWaiting() }
        AgentLog.notify.info("urgent reminder session=\(session.claudeSessionId, privacy: .public)")
    }

    private func discoverSession(jsonlURL: URL, projectHash: String, mtime: Date, isLive: Bool) {
        let claudeSessionId = jsonlURL.deletingPathExtension().lastPathComponent
        let projectName = SessionDiscovery.hashToProjectName(projectHash)
        let projectPath = "/" + projectHash.replacingOccurrences(of: "-", with: "/")

        // If a session for this claude/run id already exists (Zellij
        // surfaced it before JSONL discovered the file), just attach
        // the URL to that session instead of creating a duplicate
        // generic row. Without this, JSONL lines route to the
        // duplicate and the visible Zellij row never receives the
        // subagent / tool state — the subagent badge never appears.
        if let existingId = sessionsByClaudeId[claudeSessionId],
           let idx = sessions.firstIndex(where: { $0.id == existingId }) {
            sessionsByJsonlURL[jsonlURL] = existingId
            if sessions[idx].projectPath.isEmpty {
                sessions[idx].projectPath = projectPath
            }
            AgentLog.engine.info("attached jsonl to existing session=\(claudeSessionId, privacy: .public) project=\(projectName, privacy: .public)")
            return
        }

        var session = Session(
            claudeSessionId: claudeSessionId,
            projectName: projectName,
            projectPath: projectPath
        )
        session.lastUpdate = mtime
        session.priority = storedPriority(for: claudeSessionId)
        if !isLive {
            // Historical session — never going to be touched by the live
            // parser. Mark it done so it shows up in the OLDER list with the
            // green tint, and flag it so it's excluded from runtime tallies.
            session.activity = .done
            session.isHistorical = true
        }
        sessions.append(session)
        sessionsByJsonlURL[jsonlURL] = session.id
        sessionsByClaudeId[claudeSessionId] = session.id

        AgentLog.engine.info("discovered session=\(claudeSessionId, privacy: .public) project=\(projectName, privacy: .public) live=\(isLive)")
    }

    private func applyLine(_ line: String, jsonlURL: URL) {
        guard let id = sessionsByJsonlURL[jsonlURL],
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        let claudeId = sessions[index].claudeSessionId
        let hookActive = (lastHookEvent[claudeId].map { Date().timeIntervalSince($0) < 10 } ?? false)

        let oldActivity = sessions[index].activity

        var session = sessions[index]
        let parentToolNames = session.activeToolNames
        let events = parser.parseLineWithToolNames(
            line,
            session: &session,
            parentNames: parentToolNames
        )

        if hookActive {
            // Drop activity changes from JSONL — hook is authoritative.
            // Tool ID tracking and currentTool from JSONL still useful, but activity sticks.
            session.activity = oldActivity
        }
        sessions[index] = session

        // Drive permission timer ONLY when hooks aren't installed. With hooks
        // installed, an explicit `PermissionRequest` event is the only thing
        // that should mark a session as `.waiting` — the heuristic 5s timer
        // mis-flags long-running tools (Bash/Edit/Write) as awaiting input.
        if !HookInstaller.hooksInstalled {
            let nonExemptTool = session.activeToolNames.values.contains {
                !PermissionTimer.exemptTools.contains($0)
            }
            permissionTimer.start(for: session.claudeSessionId, hasNonExemptTool: nonExemptTool) { [weak self] in
                Task { @MainActor in
                    guard let self = self,
                          let idx = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                    let oldActivity = self.sessions[idx].activity
                    self.sessions[idx].activity = .waiting
                    self.sessions[idx].lastUpdate = Date()
                    AgentLog.engine.info("transition permission-timer session=\(self.sessions[idx].claudeSessionId, privacy: .public) \(oldActivity.logTag, privacy: .public)→waiting")
                    self.notifySessionStateChange(self.sessions[idx], oldActivity: oldActivity, source: .hook)
                }
            }
        } else {
            // Hooks are authoritative — make sure no stale timer is queued up.
            permissionTimer.cancel(for: session.claudeSessionId)
        }

        if !events.isEmpty {
            AgentLog.parser.debug("session=\(session.claudeSessionId, privacy: .public) events=\(String(describing: events), privacy: .public)")
        }
        if oldActivity != session.activity {
            AgentLog.engine.info("transition jsonl session=\(session.claudeSessionId, privacy: .public) \(oldActivity.logTag, privacy: .public)→\(session.activity.logTag, privacy: .public)")
        }

        notifySessionStateChange(session, oldActivity: oldActivity, source: .jsonl(jsonlURL))
    }

    /// Resolve the Session a hook belongs to. The Claude session id is the
    /// primary key, but a hook can arrive before the transcript file exists
    /// (`SessionStart` always does) — in which case the pane id it carries
    /// still routes it to the right Zellij row.
    private func sessionId(forHook payload: HookPayload) -> UUID? {
        if let id = sessionsByClaudeId[payload.sessionId] { return id }
        if let pane = payload.paneId {
            let matches = sessionsByZellijPane.compactMap { key, id in
                key.paneId == pane ? id : nil
            }
            if matches.count == 1 { return matches[0] }
        }
        return nil
    }

    private func applyHook(_ payload: HookPayload) {
        guard let id = sessionId(forHook: payload),
              let index = sessions.firstIndex(where: { $0.id == id }) else {
            // Neither the session id nor the pane id matches anything we know
            // about yet. The next hook event after discovery lands cleanly.
            return
        }
        let oldActivity = sessions[index].activity
        var session = sessions[index]
        session.agentKind = .claude

        // A hook is the agent speaking for itself, in real time: proof of life.
        session.lastEvidence = Date()

        // The pane id is authoritative for identity. If this row was created
        // from Zellij data alone it is still keyed by a synthetic id, so adopt
        // the real Claude session id the moment the agent tells us what it is
        // — that's what links this row to its transcript.
        if session.claudeSessionId != payload.sessionId,
           session.claudeSessionId.hasPrefix("zellij-pane-") {
            let oldId = session.claudeSessionId
            if sessionsByClaudeId[oldId] == id {
                sessionsByClaudeId.removeValue(forKey: oldId)
            }
            session.claudeSessionId = payload.sessionId
            if sessionsByClaudeId[payload.sessionId] == nil {
                sessionsByClaudeId[payload.sessionId] = id
            }
            migratePriorityKey(from: oldId, to: payload.sessionId)
        }

        switch payload.hookEvent {
        case "SessionStart":
            session.activity = .initState
        case "UserPromptSubmit":
            session.activity = .thinking
            session.currentTool = nil
        case "PreToolUse":
            if let name = payload.toolName {
                session.activity = .tool(name)
                session.currentTool = name
                // Synthetic tool ID for hook-tracked tools (parser uses real IDs from JSONL).
                let syntheticId = "hook:\(name)"
                session.activeToolNames[syntheticId] = name
                session.activeToolIds.insert(syntheticId)
            }
        case "PostToolUse", "PostToolUseFailure":
            session.activity = .thinking
            session.currentTool = nil
            if let name = payload.toolName {
                let syntheticId = "hook:\(name)"
                session.activeToolNames.removeValue(forKey: syntheticId)
                session.activeToolIds.remove(syntheticId)
            }
        case "PermissionRequest":
            session.activity = .waiting
        case "Stop", "SubagentStop", "ManualInterrupt":
            session.activity = .done
            // Lingers as .done; the .idle decay timer is M5's responsibility.
        case "SessionEnd":
            sessions[index] = session
            removeSession(id: id)
            return
        default:
            break
        }

        session.lastUpdate = Date()
        sessions[index] = session
        lastHookEvent[session.claudeSessionId] = Date()
        if oldActivity != session.activity {
            AgentLog.engine.info("transition hook session=\(session.claudeSessionId, privacy: .public) \(oldActivity.logTag, privacy: .public)→\(session.activity.logTag, privacy: .public) event=\(payload.hookEvent, privacy: .public)")
        }
        notifySessionStateChange(session, oldActivity: oldActivity, source: .hook)
    }

    private func notifySessionStateChange(
        _ session: Session,
        oldActivity: Activity,
        source: NotificationSource
    ) {
        // Phase 0.4 — source-of-truth gate. Only proceed when the
        // underlying source advanced compared to what we last saw for
        // this session. Re-running over an unchanged source produces
        // zero toasts.
        if !sourceAdvanced(for: session.id, source: source) {
            AgentLog.notify.debug("drop session=\(session.claudeSessionId, privacy: .public) reason=source-not-advanced")
            return
        }

        // If the session has visibly left the state we previously notified
        // on (waiting → tool after approval, or done → thinking after a
        // fresh prompt), clear the cached dedupe entry. The next entry back
        // into waiting/done is a genuinely new event and must not be
        // collapsed against the stale (from, to) tuple from before.
        if let last = lastNotifiedTransition[session.id],
           oldActivity == last.to,
           session.activity != last.to {
            lastNotifiedTransition.removeValue(forKey: session.id)
        }

        // Only two transitions ever produce a toast: → .waiting and → .done.
        let target: NotifyTarget
        switch session.activity {
        case .waiting where oldActivity != .waiting: target = .waiting
        case .done    where oldActivity != .done:    target = .done
        default: return
        }

        let now = Date()

        // Never toast for something we're learning about after the fact.
        // `lastUpdate` is when the transition actually happened — a replayed
        // transcript line carries its own timestamp, and a Zellij `Done`
        // carries the plugin's elapsed time — so a session first seen at
        // launch, hours after it finished, stays silent instead of firing
        // "Finished successfully" for ancient history.
        let age = now.timeIntervalSince(session.lastUpdate)
        if age > Self.staleEventCutoff {
            AgentLog.notify.info("drop session=\(session.claudeSessionId, privacy: .public) reason=stale-event age=\(Int(age))s")
            return
        }

        // Phase 0.5 — dedupe identical (from, to) within 30s.
        if let last = lastNotifiedTransition[session.id],
           last.from == oldActivity,
           last.to == session.activity,
           now.timeIntervalSince(last.firedAt) < Self.dedupeWindow {
            AgentLog.notify.info("drop session=\(session.claudeSessionId, privacy: .public) reason=dedupe \(oldActivity.logTag, privacy: .public)→\(session.activity.logTag, privacy: .public)")
            return
        }

        // Phase 0.6 — per-(session, target) throttle: 1/min per kind.
        // Waiting and done budgets are independent so a just-fired
        // "waiting" toast can't suppress the follow-up "done" toast.
        if let last = lastNotifiedAt[session.id]?[target],
           now.timeIntervalSince(last) < Self.throttleWindow {
            let kind = String(describing: target)
            AgentLog.notify.info("drop session=\(session.claudeSessionId, privacy: .public) reason=throttle target=\(kind, privacy: .public)")
            return
        }

        // Tapping the toast jumps to whichever terminal tab the agent
        // is running in, and (Phase 2.7) requests the auto-hidden notch
        // peek so the user sees that the bar is still there when the
        // toast leads them somewhere.
        let focusAction: () -> Void = { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .agentTabRequestPeek, object: nil)
            // Resolve the LATEST snapshot of this session — the cached
            // copy in the closure can go stale before the user clicks.
            if let live = self.sessions.first(where: { $0.id == session.id }) {
                self.focus(live)
            } else {
                self.focus(session)
            }
        }

        let toast: Toast
        if session.activity == .waiting {
            toast = Toast(
                variant: .attention,
                taskId: displayLabel(for: session),
                projectName: displayName(for: session),
                message: "Waiting for approval"
            )
            if soundsEnabled { soundPlayer.playWaiting() }
        } else {
            toast = Toast(
                variant: .success,
                taskId: displayLabel(for: session),
                projectName: displayName(for: session),
                message: "Finished successfully"
            )
            if soundsEnabled { soundPlayer.playDone() }
        }
        toastPanel.show(toast, duration: 5, onTap: focusAction)

        lastNotifiedTransition[session.id] = (oldActivity, session.activity, now)
        var perTarget = lastNotifiedAt[session.id] ?? [:]
        perTarget[target] = now
        lastNotifiedAt[session.id] = perTarget
        AgentLog.notify.info("fired session=\(session.claudeSessionId, privacy: .public) \(oldActivity.logTag, privacy: .public)→\(session.activity.logTag, privacy: .public)")
    }

    /// Returns true when the source's own timestamp has moved forward
    /// relative to the last value we saw for this session. JSONL:
    /// `session.lastUpdate` (parser writes Date() on each new line).
    /// Zellij: the plugin's `updated_at`. Hook: always returns true —
    /// hook events are real-time signals from the agent itself and never
    /// "replay."
    private func sourceAdvanced(for sessionId: UUID, source: NotificationSource) -> Bool {
        let timestamp: Date?
        switch source {
        case .jsonl:
            timestamp = sessions.first(where: { $0.id == sessionId })?.lastUpdate
        case .zellij(_, let updatedAt):
            timestamp = updatedAt
        case .hook:
            // Real-time. Always advance the marker so the next jsonl/
            // zellij tick doesn't see a stale baseline.
            lastSourceTimestamp[sessionId] = Date()
            return true
        }
        guard let ts = timestamp else { return true }
        if let prev = lastSourceTimestamp[sessionId], ts <= prev {
            return false
        }
        lastSourceTimestamp[sessionId] = ts
        return true
    }

    /// Apply a Zellij status snapshot. When the Zellij plugin is running it
    /// is the authoritative source of truth: every pane it reports becomes
    /// (or updates) a Session, regardless of whether a JSONL file has been
    /// discovered for that run yet. Hooks remain authoritative for activity
    /// transitions (real-time PermissionRequest, Stop, etc.); we only let
    /// Zellij overwrite activity when no recent hook has fired.
    private func applyZellijStatus(_ files: [URL: ZellijStatusFile]) {
        var seenPanes: Set<ZellijPaneKey> = []

        for (url, statusFile) in files {
            // The plugin writes one file per Zellij session, named
            // `<session-name>.json`. We need that name to focus the right
            // session via `zellij -s <session-name> action go-to-tab N`.
            let sessionName = url.deletingPathExtension().lastPathComponent
            let fileUpdatedAt = Date(timeIntervalSince1970: statusFile.updatedAt)
            for zSession in statusFile.sessions {
                seenPanes.insert(ZellijPaneKey(sessionName: sessionName, paneId: zSession.paneId))
                upsertZellijSession(zSession, sessionName: sessionName, fileUpdatedAt: fileUpdatedAt)
            }
        }

        // Prune sessions whose pane is no longer reported. Only do this
        // when the scan returned at least one file — otherwise Zellij is
        // probably mid-restart and we'd nuke the entire session list.
        if !files.isEmpty {
            pruneStaleZellijSessions(seenPanes: seenPanes)
        }
    }

    /// Tracks panes that already logged a parse failure for their
    /// `detail` field, so we only warn once per pane instead of once per
    /// 1s status refresh.
    private var warnedElapsedParseFailure: Set<ZellijPaneKey> = []

    private func upsertZellijSession(_ z: ZellijSession, sessionName: String, fileUpdatedAt: Date) {
        let info = ZellijInfo(
            paneId: z.paneId,
            tabIndex: z.tabNum,
            tabName: z.tabName,
            zellijSession: sessionName
        )
        let paneKey = ZellijPaneKey(info)
        let zellijActivity = mapZellijActivity(z)

        // The plugin republishes every pane every 5s whether or not anything
        // is still running behind it, so only a *change* in what it reports
        // carries information. Remember when each pane's current claim started
        // — for panes we can't match to a transcript, that timestamp is the
        // only thing standing between a month-dead ghost and a permanent
        // "processing" badge.
        if zellijActivityFirstSeen[paneKey]?.activity != zellijActivity {
            zellijActivityFirstSeen[paneKey] = (zellijActivity, Date())
        }

        // Only the leading component of the plugin's composite `run_id` is the
        // Claude session id — the same string the transcript filename and the
        // hook payloads use. Everything downstream keys on it.
        let resolvedClaudeId = z.runId.flatMap(Self.claudeSessionId(fromRunId:))
        let runStartedAt = z.runId.flatMap(Self.runStart(fromRunId:))
        var agentKind = AgentKind(statusValue: z.agentKind)
        if agentKind == .unknown, let resolvedClaudeId {
            agentKind = transcripts.agentKind(forSessionId: resolvedClaudeId)
        }

        // Phase 0.3 — for finished states, the plugin sends the elapsed
        // time as `5s ago` / `44m ago` / `169h ago` in `detail`. When
        // parsing succeeds we reconstruct `lastUpdate = now - elapsed`.
        // When it fails (unrecognised format), we pass `nil` so the
        // existing `lastUpdate` is PRESERVED — never stamped to `now`,
        // which would otherwise force every finished tab into RECENTLY
        // ACTIVE on each scan.
        let elapsed = elapsedSeconds(from: z.detail)
        let zellijLastUpdate: Date? = elapsed.map { Date().addingTimeInterval(-$0) }
        if zellijLastUpdate == nil, let detail = z.detail, !detail.isEmpty,
           !warnedElapsedParseFailure.contains(paneKey) {
            AgentLog.zellij.warning("could not parse elapsed='\(detail, privacy: .public)' for pane=\(z.paneId); preserving prior lastUpdate")
            warnedElapsedParseFailure.insert(paneKey)
        }

        // 1) Already linked to this pane.
        if let id = sessionsByZellijPane[paneKey],
           let index = sessions.firstIndex(where: { $0.id == id }) {
            applyZellijUpdate(at: index, info: info,
                              activity: zellijActivity,
                              lastUpdate: zellijLastUpdate,
                              runStartedAt: runStartedAt,
                              runId: resolvedClaudeId,
                              agentKind: agentKind,
                              agentTitle: z.agentTitle,
                              cwd: z.cwd,
                              fileUpdatedAt: fileUpdatedAt)
            return
        }

        // 2) JSONL discovered this run earlier and we're seeing it in
        // Zellij for the first time. Promote that existing session to a
        // Zellij session instead of creating a duplicate — otherwise the
        // JSONL row (lastUpdate=mtime, often "now-ish") would race the
        // Zellij row (lastUpdate=now-elapsed) and finish state would
        // bucket wrong.
        if let claudeId = resolvedClaudeId,
           let id = sessionsByClaudeId[claudeId],
           let index = sessions.firstIndex(where: { $0.id == id }),
           case .generic = sessions[index].terminalKind {
            sessionsByZellijPane[paneKey] = id
            applyZellijUpdate(at: index, info: info,
                              activity: zellijActivity,
                              lastUpdate: zellijLastUpdate,
                              runStartedAt: runStartedAt,
                              runId: claudeId,
                              agentKind: agentKind,
                              agentTitle: z.agentTitle,
                              cwd: z.cwd,
                              fileUpdatedAt: fileUpdatedAt)
            return
        }

        // 3) Truly new — create from Zellij data alone.
        let claudeId = resolvedClaudeId ?? "zellij-pane-\(sessionName)-\(z.paneId)"
        let projectName = z.tabName.isEmpty ? "Tab \(z.tabNum)" : z.tabName
        var session = Session(
            claudeSessionId: claudeId,
            projectName: projectName,
            // Worktree path comes from the plugin's `cwd` field. Older
            // plugin builds don't send it — then it stays empty and the
            // Finder/editor actions stay disabled for this row.
            projectPath: z.cwd ?? "",
            agentKind: agentKind
        )
        session.terminalKind = .zellij(info)
        session.activity = zellijActivity
        session.runStartedAt = runStartedAt
        session.providerSessionTitle = z.agentTitle
        session.priority = storedPriority(for: claudeId)
        // New session has no prior `lastUpdate` to preserve — fall back
        // to `now` when elapsed parsing failed.
        session.lastUpdate = zellijLastUpdate ?? Date()
        if agentKind == .devin {
            session.lastEvidence = fileUpdatedAt
        }

        // A pane can be a ghost before we've ever seen it: the plugin outlives
        // the agent, so at launch we routinely meet panes that have been
        // publishing "Thinking" since their agent died days ago. If the
        // transcript already proves that, don't let the row flash as busy for
        // the few seconds until the first sweep — it was never busy.
        if isUnbackedClaim(zellijActivity, for: session, now: Date()) {
            session.activity = .idle
            session.lastUpdate = lastEvidence(for: session, now: Date())
        }
        sessions.append(session)
        sessionsByZellijPane[paneKey] = session.id
        if let resolvedClaudeId, sessionsByClaudeId[resolvedClaudeId] == nil {
            sessionsByClaudeId[resolvedClaudeId] = session.id
        }
        AgentLog.zellij.info("discovered pane=\(z.paneId) tab=\(z.tabNum) name=\(z.tabName, privacy: .public) activity=\(z.activity, privacy: .public) elapsed=\(z.detail ?? "?", privacy: .public) session=\(sessionName, privacy: .public)")
    }

    private func applyZellijUpdate(
        at index: Int,
        info: ZellijInfo,
        activity: Activity,
        lastUpdate: Date?,
        runStartedAt: Date?,
        runId: String?,
        agentKind: AgentKind,
        agentTitle: String?,
        cwd: String?,
        fileUpdatedAt: Date
    ) {
        // Track by id, not index — the array may mutate below if we
        // merge a duplicate JSONL-only session into this one.
        let targetId = sessions[index].id
        let oldActivity = sessions[index].activity
        sessions[index].terminalKind = .zellij(info)
        sessions[index].isHistorical = false
        if let title = agentTitle, !title.isEmpty {
            sessions[index].providerSessionTitle = title
        }
        if agentKind != .unknown {
            sessions[index].agentKind = agentKind
        }
        if sessions[index].agentKind == .devin {
            // Devin has no hook bridge. A fresh plugin snapshot is direct
            // evidence because the plugin rediscovers the running process
            // from the current pane command on every PaneUpdate.
            sessions[index].lastEvidence = fileUpdatedAt
        }
        if let runStartedAt {
            sessions[index].runStartedAt = runStartedAt
        }

        // Learn / refresh the worktree path from the plugin's `cwd`.
        // Only overwrite with a non-empty value so a transient missing
        // field never clears a path we already had.
        if let cwd, !cwd.isEmpty, sessions[index].projectPath != cwd {
            sessions[index].projectPath = cwd
        }

        // Keep the runId index in sync if zellij surfaces it later.
        if let runId, sessions[index].claudeSessionId != runId {
            let oldId = sessions[index].claudeSessionId

            // If a separate session was already discovered under this
            // runId (JSONL got the file before zellij surfaced the
            // run_id), fold its tool / subagent state and JSONL URL
            // mapping into this zellij row, then remove the duplicate.
            // Without this, subagent updates land on the hidden
            // duplicate and the visible row never shows the badge.
            if let dupId = sessionsByClaudeId[runId], dupId != targetId,
               let dupIndex = sessions.firstIndex(where: { $0.id == dupId }),
               case .generic = sessions[dupIndex].terminalKind {
                mergeDuplicate(into: targetId, duplicate: dupId)
            }

            if sessionsByClaudeId[oldId] == targetId {
                sessionsByClaudeId.removeValue(forKey: oldId)
            }
            guard let idx = sessions.firstIndex(where: { $0.id == targetId }) else { return }
            sessions[idx].claudeSessionId = runId
            if sessionsByClaudeId[runId] == nil {
                sessionsByClaudeId[runId] = targetId
            }
            // Carry the user's priority assignment across the id change.
            migratePriorityKey(from: oldId, to: runId)
        }

        // Re-resolve index after the possible merge / mutation.
        guard let index = sessions.firstIndex(where: { $0.id == targetId }) else { return }
        let claudeId = sessions[index].claudeSessionId
        let hookActive = (lastHookEvent[claudeId].map { Date().timeIntervalSince($0) < 10 } ?? false)
        let activityChanged = sessions[index].activity != activity
        // The plugin has no way to know its agent died — it only decays
        // `Done → Idle`, and only evicts a pane that closes. So a pane whose
        // agent was killed keeps being published as busy indefinitely. Ignore
        // the claim outright rather than adopting it and letting the sweep
        // undo it a moment later.
        if !hookActive, isUnbackedClaim(activity, for: sessions[index], now: Date()) {
            AgentLog.zellij.debug("ignoring unbacked \(activity.logTag, privacy: .public) claim for pane=\(info.paneId)")
            return
        }
        if !hookActive, sessions[index].agentKind != .devin {
            sessions[index].activity = activity
            // Phase 0.3 — nil means "preserve existing lastUpdate".
            if let lastUpdate {
                sessions[index].lastUpdate = lastUpdate
            } else if activityChanged {
                // The plugin only puts an elapsed time in `detail` for the
                // finished states; `Waiting` and the active ones carry a tool
                // name or nothing. But a *change* in what a live status file
                // reports is itself a real-time event, so now is the correct
                // anchor. Without this the row would inherit `lastUpdate` from
                // its previous finish — minutes or hours in the past — and a
                // genuine "waiting for approval" toast would be dropped as
                // stale news.
                sessions[index].lastUpdate = Date()
            }
        }
        if oldActivity != sessions[index].activity {
            let cid = sessions[index].claudeSessionId
            let newTag = sessions[index].activity.logTag
            AgentLog.engine.info("transition zellij session=\(cid, privacy: .public) \(oldActivity.logTag, privacy: .public)→\(newTag, privacy: .public) pane=\(info.paneId)")
            notifySessionStateChange(
                sessions[index],
                oldActivity: oldActivity,
                source: .zellij(paneId: info.paneId, updatedAt: fileUpdatedAt)
            )
        }
    }

    /// Fold a duplicate session (typically a JSONL-only generic row
    /// discovered before zellij surfaced its run_id) into a target
    /// zellij row, then drop the duplicate. Carries over the tool /
    /// subagent state that the JSONL parser was populating, reroutes
    /// the duplicate's JSONL URL mappings, and clears its indices.
    private func mergeDuplicate(into targetId: UUID, duplicate dupId: UUID) {
        guard let dupIdx = sessions.firstIndex(where: { $0.id == dupId }),
              let tgtIdx = sessions.firstIndex(where: { $0.id == targetId })
        else { return }

        let dup = sessions[dupIdx]
        let dupClaudeId = dup.claudeSessionId

        // Take over JSONL-populated state — keep target's values when
        // the duplicate has nothing useful to add.
        sessions[tgtIdx].subagentTools.merge(dup.subagentTools) { _, new in new }
        sessions[tgtIdx].activeToolIds.formUnion(dup.activeToolIds)
        sessions[tgtIdx].activeToolNames.merge(dup.activeToolNames) { _, new in new }
        if sessions[tgtIdx].currentTool == nil {
            sessions[tgtIdx].currentTool = dup.currentTool
        }
        if sessions[tgtIdx].projectPath.isEmpty {
            sessions[tgtIdx].projectPath = dup.projectPath
        }
        // The duplicate is the JSONL-fed row, so it holds the transcript-derived
        // proof of life. Losing it here would leave the surviving row looking
        // silent and get it swept as stale.
        if let dupEvidence = dup.lastEvidence {
            sessions[tgtIdx].lastEvidence = max(sessions[tgtIdx].lastEvidence ?? .distantPast, dupEvidence)
        }

        // Reroute any JSONL urls that pointed at the duplicate so
        // future lines land on the visible zellij row. Note this is a
        // re-point, not a release: the file is still live and must keep
        // its watcher.
        for (url, id) in sessionsByJsonlURL where id == dupId {
            sessionsByJsonlURL[url] = targetId
        }

        // Drop the duplicate's indices and remove it from the array.
        if sessionsByClaudeId[dupClaudeId] == dupId {
            sessionsByClaudeId.removeValue(forKey: dupClaudeId)
        }
        lastSourceTimestamp.removeValue(forKey: dupId)
        lastNotifiedTransition.removeValue(forKey: dupId)
        lastNotifiedAt.removeValue(forKey: dupId)
        urgentReminders.removeValue(forKey: dupId)
        sessions.remove(at: dupIdx)

        AgentLog.engine.info("merged duplicate session into zellij row claudeId=\(dupClaudeId, privacy: .public)")
    }

    private func mapZellijActivity(_ z: ZellijSession) -> Activity {
        switch z.activity {
        // For Thinking, `detail` carries the last tool name (per the
        // plugin's status_writer); for Tool it carries the active tool
        // name. Use whichever is non-empty.
        case "Thinking":
            let tool = z.detail ?? ""
            return tool.isEmpty ? .thinking : .tool(tool)
        case "Tool":     return .tool(z.detail ?? "")
        case "Waiting":  return .waiting
        case "Done":     return .done
        case "Idle":     return .idle
        case "Init":     return .initState
        default:         return .idle
        }
    }

    /// Parse the plugin's elapsed-time strings (`5s ago`, `44m ago`,
    /// `169h ago`, `2d ago`) back into seconds so we can reconstruct
    /// `lastUpdate`. Anything unrecognised returns nil — caller falls
    /// back to "now".
    private func elapsedSeconds(from detail: String?) -> TimeInterval? {
        guard let detail, !detail.isEmpty else { return nil }
        let pattern = #"(\d+)\s*([smhd])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: detail,
                range: NSRange(detail.startIndex..., in: detail)
              ),
              let nRange = Range(match.range(at: 1), in: detail),
              let uRange = Range(match.range(at: 2), in: detail),
              let n = TimeInterval(detail[nRange])
        else { return nil }
        // Convert Substring → String explicitly. A naked `switch detail[uRange]`
        // against String literals can fail to match in some Swift releases
        // because of the Substring/String pattern-matching gap, which then
        // returns nil here and the caller stamps `lastUpdate = now` — that's
        // exactly what was forcing finished sessions into RECENTLY ACTIVE.
        let unit = String(detail[uRange])
        switch unit {
        case "s": return n
        case "m": return n * 60
        case "h": return n * 3600
        case "d": return n * 86400
        default:  return nil
        }
    }

    /// Single source of truth for the green-pill count and the
    /// RECENTLY ACTIVE list. Compact and expanded read the same
    /// predicate so they never disagree. The plugin marks a session
    /// as `Idle` once it's been quiet for a while — both `.done` and
    /// `.idle` count as "finished," with the elapsed-time cutoff
    /// deciding whether the row belongs in RECENTLY or OLDER.
    func recentlyActiveDoneSessions() -> [Session] {
        let cutoff = Date().addingTimeInterval(-ActivityEngine.recentFinishedWindow)
        return displaySessions
            .filter { s in
                switch s.activity {
                case .done, .idle:
                    guard !s.isHistorical else { return false }
                    // Urgent tabs never age out into OLDER FINISHED —
                    // they stay in RECENTLY ACTIVE regardless of how
                    // much time has passed since they finished.
                    if s.priority == .urgent { return true }
                    return s.lastUpdate >= cutoff
                default:
                    return false
                }
            }
            .sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private func pruneStaleZellijSessions(seenPanes: Set<ZellijPaneKey>) {
        let stale: [UUID] = sessions.compactMap { session -> UUID? in
            if case .zellij(let info) = session.terminalKind,
               !seenPanes.contains(ZellijPaneKey(info)) {
                return session.id
            }
            return nil
        }
        for id in stale {
            removeSession(id: id)
        }
    }
}
