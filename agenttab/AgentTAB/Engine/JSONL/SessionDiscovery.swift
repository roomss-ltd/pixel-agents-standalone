import Foundation

enum SessionDiscovery {
    /// Recover a display name like "my-repo" or "my-repo/feat-x" from a Claude
    /// projects-directory hash like "-Users-adi-Desktop-my-repo--worktrees-feat-x".
    static func hashToProjectName(_ hash: String) -> String {
        let parts = hash.split(separator: "-").filter { !$0.isEmpty }.map(String.init)
        guard let desktopIdx = parts.firstIndex(of: "Desktop") else {
            return parts.last ?? hash
        }
        let afterDesktop = Array(parts[(desktopIdx + 1)...])
        guard let worktreeIdx = afterDesktop.firstIndex(where: { $0 == "worktrees" || $0 == "worktree" }) else {
            return afterDesktop.joined(separator: "-")
        }
        let repo = afterDesktop[..<worktreeIdx].joined(separator: "-")
        let branch = afterDesktop[(worktreeIdx + 1)...].joined(separator: "-")
        return branch.isEmpty ? repo : "\(repo)/\(branch)"
    }

    static func pathToProjectName(_ path: String) -> String {
        let parts = URL(fileURLWithPath: path).standardized.pathComponents
        if let worktrees = parts.lastIndex(of: ".worktrees"), worktrees > 0,
           worktrees + 1 < parts.count {
            return "\(parts[worktrees - 1])/\(parts[worktrees + 1])"
        }
        return parts.last ?? path
    }
}

/// Locates a Claude transcript or Codex rollout and reports when the agent
/// last wrote to it.
///
/// The mtime is the one liveness signal that cannot lie. Claude appends to its
/// transcript as it works, so a file that hasn't grown in N minutes belongs to
/// an agent that isn't working — or isn't running at all. Every other signal we
/// have is a *claim*: hooks stop arriving when a process is killed rather than
/// exiting, and the Zellij plugin keeps re-publishing a pane's last known
/// activity every 5s forever, whether or not anything is still behind it.
///
/// This deliberately looks across the whole projects directory rather than the
/// recent window `JSONLWatcher` tracks: a ghost session's transcript is often
/// days old, and that age is precisely the evidence we need.
final class TranscriptLocator {
    private let projectsDir: URL
    private let codexSessionsDir: URL?

    /// sessionId → (transcript URL, or nil when we looked and found nothing).
    /// Negative results are cached too but expire, so a session whose file
    /// doesn't exist yet is found once it appears.
    private var lookups: [String: (url: URL?, kind: AgentKind, at: Date)] = [:]
    private static let missTTL: TimeInterval = 30
    private static let defaultProjectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private static let defaultCodexSessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    init(projectsDir: URL = TranscriptLocator.defaultProjectsDir, codexSessionsDir: URL? = nil) {
        self.projectsDir = projectsDir
        self.codexSessionsDir = codexSessionsDir ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultCodexSessionsDir
                : nil
        )
    }

    /// When the agent last appended to its transcript, or nil if we can't find
    /// one for this session (a Zellij-only pane we've never matched, or a
    /// transcript outside the supported stores).
    func lastWrite(forSessionId sessionId: String, now: Date = Date()) -> Date? {
        guard let location = locate(sessionId, now: now) else { return nil }
        return (try? location.url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    func agentKind(forSessionId sessionId: String, now: Date = Date()) -> AgentKind {
        locate(sessionId, now: now)?.kind ?? .unknown
    }

    private func locate(_ sessionId: String, now: Date) -> (url: URL, kind: AgentKind)? {
        // Synthetic ids (`zellij-pane-7`) and anything path-shaped can never
        // name a transcript — don't burn a directory scan on them.
        guard !sessionId.isEmpty,
              !sessionId.contains("/"),
              !sessionId.contains(":"),
              !sessionId.hasPrefix("zellij-pane-")
        else { return nil }

        if let cached = lookups[sessionId] {
            if let url = cached.url {
                if FileManager.default.fileExists(atPath: url.path) {
                    return (url, cached.kind)
                }
            } else if now.timeIntervalSince(cached.at) < Self.missTTL {
                return nil
            }
        }

        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for projectURL in projects {
            let candidate = projectURL.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: candidate.path) {
                lookups[sessionId] = (candidate, .claude, now)
                return (candidate, .claude)
            }
        }

        if let codexSessionsDir,
           let enumerator = fm.enumerator(
                at: codexSessionsDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
           ) {
            for case let candidate as URL in enumerator
            where candidate.pathExtension == "jsonl"
                && candidate.lastPathComponent.contains(sessionId) {
                lookups[sessionId] = (candidate, .codex, now)
                return (candidate, .codex)
            }
        }

        lookups[sessionId] = (nil, .unknown, now)
        return nil
    }
}

/// Reads Codex's parent-thread metadata and the latest child lifecycle event.
/// Active grandchildren are counted for each ancestor so a root tab shows the
/// complete running tree while token accounting still counts every rollout.
enum CodexSubagentScanner {
    private struct ChildState {
        let id: String
        let parentId: String
        let isActive: Bool
    }

    static func activeCounts(sessionsDir: URL, now: Date = Date()) -> [String: Int] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var children: [ChildState] = []
        let oldestRelevant = now.addingTimeInterval(-7 * 24 * 3600)
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  (values?.contentModificationDate ?? .distantPast) >= oldestRelevant,
                  let state = childState(in: file)
            else { continue }
            children.append(state)
        }

        let parentByChild = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0.parentId) })
        var counts: [String: Int] = [:]
        for child in children where child.isActive {
            var ancestor = child.parentId
            var visited: Set<String> = [child.id]
            while !ancestor.isEmpty, visited.insert(ancestor).inserted {
                counts[ancestor, default: 0] += 1
                guard let next = parentByChild[ancestor] else { break }
                ancestor = next
            }
        }
        return counts
    }

    private static func childState(in file: URL) -> ChildState? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        let head = handle.readData(ofLength: Int(min(end, 128 * 1024)))
        guard let headText = String(data: head, encoding: .utf8),
              let firstLine = headText.split(separator: "\n", maxSplits: 1).first,
              let meta = json(firstLine),
              meta["type"] as? String == "session_meta",
              let payload = meta["payload"] as? [String: Any],
              let id = (payload["id"] as? String) ?? (payload["session_id"] as? String),
              let source = payload["source"] as? [String: Any],
              let subagent = source["subagent"] as? [String: Any],
              let spawn = subagent["thread_spawn"] as? [String: Any],
              let parentId = spawn["parent_thread_id"] as? String
        else { return nil }

        let tailSize = min(end, 512 * 1024)
        try? handle.seek(toOffset: end - tailSize)
        let tail = handle.readData(ofLength: Int(tailSize))
        let tailText = String(data: tail, encoding: .utf8) ?? ""
        var isActive = true
        for line in tailText.split(separator: "\n") {
            guard let record = json(line),
                  record["type"] as? String == "event_msg",
                  let event = record["payload"] as? [String: Any],
                  let type = event["type"] as? String
            else { continue }
            if type == "task_started" { isActive = true }
            if type == "task_complete" || type == "turn_aborted" { isActive = false }
        }
        return ChildState(id: id, parentId: parentId, isActive: isActive)
    }

    private static func json<S: StringProtocol>(_ line: S) -> [String: Any]? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
