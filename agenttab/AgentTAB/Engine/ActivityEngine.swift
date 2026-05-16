import Foundation
import Combine
import SwiftUI

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    /// True once the Zellij plugin has been detected on the system. While
    /// active, the UI only counts/shows sessions matched to a real Zellij
    /// pane — historical jsonl files that don't correspond to a live tab
    /// are hidden so the OLDER list mirrors what Hammerspoon would show.
    @Published private(set) var zellijDetected: Bool = false

    /// User-dismissed Zellij panes. The unlink button in the expanded
    /// panel adds a pane id here; the session is then filtered out of
    /// `displaySessions` until the user reopens it manually.
    @Published private var deniedPaneIds: Set<Int> = []

    /// Hide a session from the panel. Currently only Zellij sessions are
    /// dismissible — for non-Zellij the unlink button is a no-op.
    func hide(_ session: Session) {
        if case .zellij(let info) = session.terminalKind {
            deniedPaneIds.insert(info.paneId)
        }
    }

    /// View-facing session list. When the Zellij plugin is active AND has
    /// successfully matched at least one session, we trust its view of the
    /// world and only surface Zellij-tagged sessions. Until the first match
    /// lands (or if Zellij isn't running) we show everything the JSONL
    /// watcher has discovered — the watcher already caps historical files.
    var displaySessions: [Session] {
        let denied = deniedPaneIds
        let withoutDenied = sessions.filter { s -> Bool in
            if case .zellij(let info) = s.terminalKind {
                return !denied.contains(info.paneId)
            }
            return true
        }
        guard zellijDetected else { return withoutDenied }
        let zellijOnly = withoutDenied.filter {
            if case .zellij = $0.terminalKind { return true } else { return false }
        }
        return zellijOnly.isEmpty ? withoutDenied : zellijOnly
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
            let peers = displaySessions
                .compactMap { s -> ZellijInfo? in
                    if case .zellij(let i) = s.terminalKind, i.tabIndex == info.tabIndex {
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

            // 2. Run the zellij focus command through a login shell so
            //    PATH (cargo / brew / etc.) is loaded.
            let escapedSession = info.zellijSession
                .replacingOccurrences(of: "'", with: "'\\''")
            var cmd = "zellij"
            if !info.zellijSession.isEmpty {
                cmd += " -s '\(escapedSession)'"
            }
            cmd += " action go-to-tab \(info.tabIndex)"

            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-l", "-c", cmd]
            do {
                try task.run()
            } catch {
                print("[Engine] zellij focus failed: \(error)")
            }
        case .generic:
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: session.projectPath)]
            )
        }
    }

    /// Mirrors the Hammerspoon webview's `RECENT_FINISHED_WINDOW_SECONDS`
    /// — anything finished within this many seconds counts as
    /// "recently active"; anything older falls into "OLDER FINISHED" and
    /// is excluded from the green badge.
    static let recentFinishedWindow: TimeInterval = 3 * 3600   // 3 hours

    /// Tab-index sort key — ascending zellij `tab_num`, then `paneId` to
    /// keep collisions stable. Non-zellij sessions sort to the end.
    static func byTabIndexAsc(_ a: Session, _ b: Session) -> Bool {
        let ai = tabIndex(of: a)
        let bi = tabIndex(of: b)
        if ai.tab != bi.tab { return ai.tab < bi.tab }
        return ai.pane < bi.pane
    }

    private static func tabIndex(of s: Session) -> (tab: Int, pane: Int) {
        if case .zellij(let info) = s.terminalKind {
            return (info.tabIndex, info.paneId)
        }
        return (Int.max, Int.max)
    }

    private var sessionsByJsonlURL: [URL: UUID] = [:]
    private var sessionsByClaudeId: [String: UUID] = [:]
    /// When the Zellij plugin is the authoritative source we key sessions
    /// by zellij `pane_id` — that lets us upsert without depending on a
    /// JSONL file having been discovered first, and lets us prune cleanly
    /// when the pane disappears from the status files.
    private var sessionsByZellijPaneId: [Int: UUID] = [:]

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

    /// Per-session dedupe: identical (from, to) within 30s collapses.
    private var lastNotifiedTransition: [UUID: (from: Activity, to: Activity, firedAt: Date)] = [:]

    /// Global per-session throttle: at most one toast per minute.
    private var lastNotifiedAt: [UUID: Date] = [:]

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
    private let parser = TranscriptParser()
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

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.jsonlWatcher = JSONLWatcher(projectsDir: projectsDir)
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

        let probe = EnvironmentProbe.detect()
        if probe.pluginState == .producingStatusFiles {
            zellijDetected = true
            zellijReader = ZellijStatusReader()
            zellijReader?.onUpdate = { [weak self] fileMap in
                Task { @MainActor in self?.applyZellijStatus(fileMap) }
            }
            zellijReader?.start()
            print("[Engine] Zellij status reader active")
        }

        startUrgentReminderTimer()
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
        let events = parser.parseLine(line, session: &session)

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

    private func applyHook(_ payload: HookPayload) {
        guard let id = sessionsByClaudeId[payload.sessionId],
              let index = sessions.firstIndex(where: { $0.id == id }) else {
            // Hook fired before JSONL discovered this session — buffer or wait.
            // For v1, drop. The next hook event after JSONL discovery will land cleanly.
            return
        }
        let oldActivity = sessions[index].activity
        var session = sessions[index]

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
            sessions.remove(at: index)
            sessionsByJsonlURL = sessionsByJsonlURL.filter { $0.value != id }
            sessionsByClaudeId.removeValue(forKey: payload.sessionId)
            return
        default:
            break
        }

        session.lastUpdate = Date()
        sessions[index] = session
        lastHookEvent[payload.sessionId] = Date()
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

        // Only two transitions ever produce a toast: → .waiting and → .done.
        let interesting =
            (session.activity == .waiting && oldActivity != .waiting) ||
            (session.activity == .done    && oldActivity != .done)
        guard interesting else { return }

        // Phase 0.5 — dedupe identical (from, to) within 30s.
        let now = Date()
        if let last = lastNotifiedTransition[session.id],
           last.from == oldActivity,
           last.to == session.activity,
           now.timeIntervalSince(last.firedAt) < Self.dedupeWindow {
            AgentLog.notify.info("drop session=\(session.claudeSessionId, privacy: .public) reason=dedupe \(oldActivity.logTag, privacy: .public)→\(session.activity.logTag, privacy: .public)")
            return
        }

        // Phase 0.6 — global per-session throttle: 1/min.
        if let last = lastNotifiedAt[session.id],
           now.timeIntervalSince(last) < Self.throttleWindow {
            AgentLog.notify.info("drop session=\(session.claudeSessionId, privacy: .public) reason=throttle")
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
        lastNotifiedAt[session.id] = now
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
        var seenPaneIds: Set<Int> = []

        for (url, statusFile) in files {
            // The plugin writes one file per Zellij session, named
            // `<session-name>.json`. We need that name to focus the right
            // session via `zellij -s <session-name> action go-to-tab N`.
            let sessionName = url.deletingPathExtension().lastPathComponent
            let fileUpdatedAt = Date(timeIntervalSince1970: statusFile.updatedAt)
            for zSession in statusFile.sessions {
                seenPaneIds.insert(zSession.paneId)
                upsertZellijSession(zSession, sessionName: sessionName, fileUpdatedAt: fileUpdatedAt)
            }
        }

        // Prune sessions whose pane is no longer reported. Only do this
        // when the scan returned at least one file — otherwise Zellij is
        // probably mid-restart and we'd nuke the entire session list.
        if !files.isEmpty {
            pruneStaleZellijSessions(seenPaneIds: seenPaneIds)
        }
    }

    /// Tracks panes that already logged a parse failure for their
    /// `detail` field, so we only warn once per pane instead of once per
    /// 1s status refresh.
    private var warnedElapsedParseFailure: Set<Int> = []

    private func upsertZellijSession(_ z: ZellijSession, sessionName: String, fileUpdatedAt: Date) {
        let info = ZellijInfo(
            paneId: z.paneId,
            tabIndex: z.tabNum,
            tabName: z.tabName,
            zellijSession: sessionName
        )
        let zellijActivity = mapZellijActivity(z)

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
           !warnedElapsedParseFailure.contains(z.paneId) {
            AgentLog.zellij.warning("could not parse elapsed='\(detail, privacy: .public)' for pane=\(z.paneId); preserving prior lastUpdate")
            warnedElapsedParseFailure.insert(z.paneId)
        }

        // 1) Already linked to this pane.
        if let id = sessionsByZellijPaneId[z.paneId],
           let index = sessions.firstIndex(where: { $0.id == id }) {
            applyZellijUpdate(at: index, info: info,
                              activity: zellijActivity,
                              lastUpdate: zellijLastUpdate,
                              runId: z.runId,
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
        if let runId = z.runId,
           let id = sessionsByClaudeId[runId],
           let index = sessions.firstIndex(where: { $0.id == id }) {
            sessionsByZellijPaneId[z.paneId] = id
            applyZellijUpdate(at: index, info: info,
                              activity: zellijActivity,
                              lastUpdate: zellijLastUpdate,
                              runId: runId,
                              cwd: z.cwd,
                              fileUpdatedAt: fileUpdatedAt)
            return
        }

        // 3) Truly new — create from Zellij data alone.
        let claudeId = z.runId ?? "zellij-pane-\(z.paneId)"
        let projectName = z.tabName.isEmpty ? "Tab \(z.tabNum)" : z.tabName
        var session = Session(
            claudeSessionId: claudeId,
            projectName: projectName,
            // Worktree path comes from the plugin's `cwd` field. Older
            // plugin builds don't send it — then it stays empty and the
            // Finder/editor actions stay disabled for this row.
            projectPath: z.cwd ?? ""
        )
        session.terminalKind = .zellij(info)
        session.activity = zellijActivity
        session.priority = storedPriority(for: claudeId)
        // New session has no prior `lastUpdate` to preserve — fall back
        // to `now` when elapsed parsing failed.
        session.lastUpdate = zellijLastUpdate ?? Date()
        sessions.append(session)
        sessionsByZellijPaneId[z.paneId] = session.id
        if let runId = z.runId {
            sessionsByClaudeId[runId] = session.id
        }
        AgentLog.zellij.info("discovered pane=\(z.paneId) tab=\(z.tabNum) name=\(z.tabName, privacy: .public) activity=\(z.activity, privacy: .public) elapsed=\(z.detail ?? "?", privacy: .public) session=\(sessionName, privacy: .public)")
    }

    private func applyZellijUpdate(
        at index: Int,
        info: ZellijInfo,
        activity: Activity,
        lastUpdate: Date?,
        runId: String?,
        cwd: String?,
        fileUpdatedAt: Date
    ) {
        // Track by id, not index — the array may mutate below if we
        // merge a duplicate JSONL-only session into this one.
        let targetId = sessions[index].id
        let oldActivity = sessions[index].activity
        sessions[index].terminalKind = .zellij(info)
        sessions[index].isHistorical = false

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
            if let dupId = sessionsByClaudeId[runId], dupId != targetId {
                mergeDuplicate(into: targetId, duplicate: dupId)
            }

            sessionsByClaudeId.removeValue(forKey: oldId)
            guard let idx = sessions.firstIndex(where: { $0.id == targetId }) else { return }
            sessions[idx].claudeSessionId = runId
            sessionsByClaudeId[runId] = targetId
            // Carry the user's priority assignment across the id change.
            migratePriorityKey(from: oldId, to: runId)
        }

        // Re-resolve index after the possible merge / mutation.
        guard let index = sessions.firstIndex(where: { $0.id == targetId }) else { return }
        let claudeId = sessions[index].claudeSessionId
        let hookActive = (lastHookEvent[claudeId].map { Date().timeIntervalSince($0) < 10 } ?? false)
        if !hookActive {
            sessions[index].activity = activity
            // Phase 0.3 — nil means "preserve existing lastUpdate".
            if let lastUpdate {
                sessions[index].lastUpdate = lastUpdate
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

        // Reroute any JSONL urls that pointed at the duplicate so
        // future lines land on the visible zellij row.
        for (url, id) in sessionsByJsonlURL where id == dupId {
            sessionsByJsonlURL[url] = targetId
        }

        // Drop the duplicate's indices and remove it from the array.
        if sessionsByClaudeId[dupClaudeId] == dupId {
            sessionsByClaudeId.removeValue(forKey: dupClaudeId)
        }
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

    private func pruneStaleZellijSessions(seenPaneIds: Set<Int>) {
        let stale: [Int] = sessions.indices.compactMap { idx -> Int? in
            if case .zellij(let info) = sessions[idx].terminalKind,
               !seenPaneIds.contains(info.paneId) {
                return idx
            }
            return nil
        }
        for idx in stale.reversed() {
            let session = sessions[idx]
            if case .zellij(let info) = session.terminalKind {
                sessionsByZellijPaneId.removeValue(forKey: info.paneId)
            }
            sessionsByClaudeId.removeValue(forKey: session.claudeSessionId)
            sessions.remove(at: idx)
        }
    }
}
