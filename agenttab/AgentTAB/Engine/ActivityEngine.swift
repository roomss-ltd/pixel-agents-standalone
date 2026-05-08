import Foundation
import Combine
import SwiftUI

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private var sessionsByJsonlURL: [URL: UUID] = [:]
    private var sessionsByClaudeId: [String: UUID] = [:]
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
        jsonlWatcher.onSessionDiscovered = { [weak self] url, projectHash in
            Task { @MainActor in self?.discoverSession(jsonlURL: url, projectHash: projectHash) }
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
            zellijReader = ZellijStatusReader()
            zellijReader?.onUpdate = { [weak self] fileMap in
                Task { @MainActor in self?.applyZellijStatus(fileMap) }
            }
            zellijReader?.start()
            print("[Engine] Zellij status reader active")
        }
    }

    private func discoverSession(jsonlURL: URL, projectHash: String) {
        let claudeSessionId = jsonlURL.deletingPathExtension().lastPathComponent
        let projectName = SessionDiscovery.hashToProjectName(projectHash)
        let projectPath = "/" + projectHash.replacingOccurrences(of: "-", with: "/")

        let session = Session(
            claudeSessionId: claudeSessionId,
            projectName: projectName,
            projectPath: projectPath
        )
        sessions.append(session)
        sessionsByJsonlURL[jsonlURL] = session.id
        sessionsByClaudeId[claudeSessionId] = session.id

        print("[Engine] New session: \(claudeSessionId) (\(projectName))")
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

        // Drive permission timer based on session state
        let nonExemptTool = session.activeToolIds.contains { _ in true }
        permissionTimer.start(for: session.claudeSessionId, hasNonExemptTool: nonExemptTool) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      let idx = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                let oldActivity = self.sessions[idx].activity
                self.sessions[idx].activity = .waiting
                self.notifySessionStateChange(self.sessions[idx], oldActivity: oldActivity)
            }
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
            }
        case "PostToolUse", "PostToolUseFailure":
            session.activity = .thinking
            session.currentTool = nil
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
        if session.activity == .waiting && oldActivity != .waiting {
            let toast = Toast(
                title: "Claude needs your input",
                subtitle: session.projectName,
                activity: .waiting
            )
            toastPanel.show(toast, corner: toastCorner, duration: 8)
            if soundsEnabled { soundPlayer.playWaiting() }
        } else if session.activity == .done && oldActivity != .done {
            let toast = Toast(
                title: "Finished",
                subtitle: session.projectName,
                activity: .done
            )
            toastPanel.show(toast, corner: toastCorner, duration: 4)
            if soundsEnabled { soundPlayer.playDone() }
        }
    }

    private func applyZellijStatus(_ files: [URL: ZellijStatusFile]) {
        for (_, statusFile) in files {
            for zSession in statusFile.sessions {
                // Match AgentTAB session by claudeSessionId (which equals run_id from the plugin output).
                guard let runId = zSession.runId,
                      let id = sessionsByClaudeId[runId],
                      let index = sessions.firstIndex(where: { $0.id == id }) else { continue }

                sessions[index].terminalKind = .zellij(ZellijInfo(
                    paneId: zSession.paneId,
                    tabIndex: zSession.tabNum,
                    tabName: zSession.tabName,
                    zellijSession: ""    // not currently in the plugin's output
                ))
            }
        }
    }
}
