import Foundation
import Combine

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private var sessionsByJsonlURL: [URL: UUID] = [:]
    private var sessionsByClaudeId: [String: UUID] = [:]
    private let parser = TranscriptParser()
    private let permissionTimer = PermissionTimer()
    private let jsonlWatcher: JSONLWatcher

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
        var session = sessions[index]
        let events = parser.parseLine(line, session: &session)
        sessions[index] = session

        // Drive permission timer based on session state
        let nonExemptTool = session.activeToolIds.contains { _ in
            // For now, assume any active tool may need permission unless we track names.
            // The parser already excludes Read/Grep/Glob if those happen; the engine refines this in M4 with hook payloads.
            true
        }
        permissionTimer.start(for: session.claudeSessionId, hasNonExemptTool: nonExemptTool) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      let idx = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                self.sessions[idx].activity = .waiting
            }
        }

        if !events.isEmpty {
            print("[Engine] Session \(session.claudeSessionId): \(events)")
        }
    }
}
