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
}

/// Locates a Claude session's transcript on disk and reports when the agent
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

    /// sessionId → (transcript URL, or nil when we looked and found nothing).
    /// Negative results are cached too but expire, so a session whose file
    /// doesn't exist yet is found once it appears.
    private var lookups: [String: (url: URL?, at: Date)] = [:]
    private static let missTTL: TimeInterval = 30

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }

    /// When the agent last appended to its transcript, or nil if we can't find
    /// one for this session (a Zellij-only pane we've never matched, a Codex
    /// agent, a transcript outside `projectsDir`).
    func lastWrite(forSessionId sessionId: String, now: Date = Date()) -> Date? {
        guard let url = locate(sessionId, now: now) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    private func locate(_ sessionId: String, now: Date) -> URL? {
        // Synthetic ids (`zellij-pane-7`) and anything path-shaped can never
        // name a transcript — don't burn a directory scan on them.
        guard !sessionId.isEmpty,
              !sessionId.contains("/"),
              !sessionId.contains(":"),
              !sessionId.hasPrefix("zellij-pane-")
        else { return nil }

        if let cached = lookups[sessionId] {
            if let url = cached.url {
                if FileManager.default.fileExists(atPath: url.path) { return url }
            } else if now.timeIntervalSince(cached.at) < Self.missTTL {
                return nil
            }
        }

        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for projectURL in projects {
            let candidate = projectURL.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: candidate.path) {
                lookups[sessionId] = (candidate, now)
                return candidate
            }
        }
        lookups[sessionId] = (nil, now)
        return nil
    }
}
