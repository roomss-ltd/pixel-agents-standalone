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
    }

    private func discoverSession(jsonlURL: URL, projectHash: String, mtime: Date, isLive: Bool) {
        let claudeSessionId = jsonlURL.deletingPathExtension().lastPathComponent
        let projectName = SessionDiscovery.hashToProjectName(projectHash)
        let projectPath = "/" + projectHash.replacingOccurrences(of: "-", with: "/")

        var session = Session(
            claudeSessionId: claudeSessionId,
            projectName: projectName,
            projectPath: projectPath
        )
        session.lastUpdate = mtime
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

        print("[Engine] \(isLive ? "Live" : "Historical") session: \(claudeSessionId) (\(projectName))")
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
                    self.notifySessionStateChange(self.sessions[idx], oldActivity: oldActivity)
                }
            }
        } else {
            // Hooks are authoritative — make sure no stale timer is queued up.
            permissionTimer.cancel(for: session.claudeSessionId)
        }

        if !events.isEmpty {
            print("[Engine] Session \(session.claudeSessionId): \(events)")
        }

        notifySessionStateChange(session, oldActivity: oldActivity)
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
        notifySessionStateChange(session, oldActivity: oldActivity)
    }

    private func notifySessionStateChange(_ session: Session, oldActivity: Activity) {
        // Tapping the toast jumps to whichever terminal tab the agent
        // is running in. Same focus path the expanded panel uses.
        let focusAction: () -> Void = { [weak self] in
            guard let self else { return }
            // Resolve the LATEST snapshot of this session — the cached
            // copy in the closure can go stale before the user clicks.
            if let live = self.sessions.first(where: { $0.id == session.id }) {
                self.focus(live)
            } else {
                self.focus(session)
            }
        }

        if session.activity == .waiting && oldActivity != .waiting {
            let toast = Toast(
                variant: .attention,
                taskId: displayLabel(for: session),
                projectName: displayName(for: session),
                message: "Waiting for approval"
            )
            toastPanel.show(toast, duration: 5, onTap: focusAction)
            if soundsEnabled { soundPlayer.playWaiting() }
        } else if session.activity == .done && oldActivity != .done {
            let toast = Toast(
                variant: .success,
                taskId: displayLabel(for: session),
                projectName: displayName(for: session),
                message: "Finished successfully"
            )
            toastPanel.show(toast, duration: 5, onTap: focusAction)
            if soundsEnabled { soundPlayer.playDone() }
        }
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
            for zSession in statusFile.sessions {
                seenPaneIds.insert(zSession.paneId)
                upsertZellijSession(zSession, sessionName: sessionName)
            }
        }

        // Prune sessions whose pane is no longer reported. Only do this
        // when the scan returned at least one file — otherwise Zellij is
        // probably mid-restart and we'd nuke the entire session list.
        if !files.isEmpty {
            pruneStaleZellijSessions(seenPaneIds: seenPaneIds)
        }
    }

    private func upsertZellijSession(_ z: ZellijSession, sessionName: String) {
        let info = ZellijInfo(
            paneId: z.paneId,
            tabIndex: z.tabNum,
            tabName: z.tabName,
            zellijSession: sessionName
        )
        let zellijActivity = mapZellijActivity(z)
        // For finished states, the plugin sends the elapsed time as
        // `5s ago` / `44m ago` / `169h ago` in `detail`. Parsing that
        // back lets us bucket sessions correctly into RECENTLY ACTIVE
        // (≤1h) vs OLDER FINISHED (>1h) — without it every refresh
        // would stamp `lastUpdate = now`, forcing every finished tab
        // into "recently active" forever.
        let elapsed = elapsedSeconds(from: z.detail)
        let zellijLastUpdate: Date = elapsed.map { Date().addingTimeInterval(-$0) } ?? Date()

        // 1) Already linked to this pane.
        if let id = sessionsByZellijPaneId[z.paneId],
           let index = sessions.firstIndex(where: { $0.id == id }) {
            applyZellijUpdate(at: index, info: info,
                              activity: zellijActivity,
                              lastUpdate: zellijLastUpdate,
                              runId: z.runId)
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
                              runId: runId)
            return
        }

        // 3) Truly new — create from Zellij data alone.
        let claudeId = z.runId ?? "zellij-pane-\(z.paneId)"
        let projectName = z.tabName.isEmpty ? "Tab \(z.tabNum)" : z.tabName
        var session = Session(
            claudeSessionId: claudeId,
            projectName: projectName,
            projectPath: ""
        )
        session.terminalKind = .zellij(info)
        session.activity = zellijActivity
        session.lastUpdate = zellijLastUpdate
        sessions.append(session)
        sessionsByZellijPaneId[z.paneId] = session.id
        if let runId = z.runId {
            sessionsByClaudeId[runId] = session.id
        }
        print("[Engine] Zellij session: pane=\(z.paneId) tab=\(z.tabNum) name=\(z.tabName) activity=\(z.activity) elapsed=\(z.detail ?? "?") session=\(sessionName)")
    }

    private func applyZellijUpdate(
        at index: Int,
        info: ZellijInfo,
        activity: Activity,
        lastUpdate: Date,
        runId: String?
    ) {
        let oldActivity = sessions[index].activity
        sessions[index].terminalKind = .zellij(info)
        sessions[index].isHistorical = false

        // Keep the runId index in sync if zellij surfaces it later.
        if let runId, sessions[index].claudeSessionId != runId {
            sessionsByClaudeId.removeValue(forKey: sessions[index].claudeSessionId)
            sessions[index].claudeSessionId = runId
            sessionsByClaudeId[runId] = sessions[index].id
        }

        let claudeId = sessions[index].claudeSessionId
        let hookActive = (lastHookEvent[claudeId].map { Date().timeIntervalSince($0) < 10 } ?? false)
        if !hookActive {
            sessions[index].activity = activity
            sessions[index].lastUpdate = lastUpdate
        }
        if oldActivity != sessions[index].activity {
            notifySessionStateChange(sessions[index], oldActivity: oldActivity)
        }
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
                    return !s.isHistorical && s.lastUpdate >= cutoff
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
