// TokenTracker — per-machine daily token-spend counter.
//
// Sums token usage across every Claude Code agent that ran today by
// scanning ~/.claude/projects/**/*.jsonl. Only `assistant` lines with
// a today-dated `timestamp` are counted; the total is
// input + output + cache_creation + cache_read tokens.
//
// Scanning is incremental — each file keeps a byte cursor so a refresh
// only parses bytes appended since the last pass. The counter resets
// automatically when the local date rolls over (it's the source of
// truth recomputed from today's lines, so no persistence is needed).

import Foundation
import Combine

/// One day's slice of agent activity, used by the weekly history view.
struct DailyActivity: Identifiable, Equatable {
    var id: Date { day }
    let day: Date           // start of day
    let tokens: Int         // total tokens spent that day
    let agentCount: Int     // distinct agent sessions active that day
    let projects: [String]  // project names worked on that day
}

/// A project's total token spend over the weekly window — "what the
/// agents were working on."
struct ProjectSpend: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let tokens: Int
    let activeDays: Int
}

@MainActor
final class TokenTracker: ObservableObject {
    /// Total tokens spent across all agents on the local machine today.
    @Published private(set) var todayTokens: Int = 0

    /// Last-7-days breakdown, populated on demand by `refreshWeekly()`.
    /// Always exactly 7 entries, oldest first, including zero days.
    @Published private(set) var weekly: [DailyActivity] = []

    /// Projects worked on across the weekly window, sorted by token
    /// spend descending. Populated alongside `weekly`.
    @Published private(set) var weeklyProjects: [ProjectSpend] = []

    private let projectsDir: URL
    private var timer: AnyCancellable?

    /// Compact human formatting: 1_234 → "1.2K", 5_000_000 → "5.0M",
    /// 2_000_000_000 → "2.0B", 3_000_000_000_000 → "3.0T".
    static func format(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000_000 { return String(format: "%.1fT", d / 1_000_000_000_000) }
        if d >= 1_000_000_000     { return String(format: "%.1fB", d / 1_000_000_000) }
        if d >= 1_000_000         { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000             { return String(format: "%.1fK", d / 1_000) }
        return "\(n)"
    }

    /// Per-file scan cursor — byte offset already summed.
    private var fileCursors: [URL: UInt64] = [:]

    /// The start-of-day the running total belongs to. When the wall
    /// clock crosses midnight we reset everything.
    private var currentDay: Date = Calendar.current.startOfDay(for: Date())

    /// Reused — ISO8601DateFormatter is expensive to allocate per line.
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFraction = ISO8601DateFormatter()

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }

    func start() {
        refresh()
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Recompute the delta since the last pass. Cheap to call often —
    /// safe to invoke on panel-expand for a fresh number.
    func refresh() {
        // Date rollover → wipe and start the new day at zero.
        let today = Calendar.current.startOfDay(for: Date())
        if today != currentDay {
            currentDay = today
            fileCursors.removeAll()
            todayTokens = 0
            AgentLog.engine.info("token tracker reset for new day")
        }

        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return }

        var added = 0
        for project in projects {
            guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir,
                  let files = try? FileManager.default.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: [.contentModificationDateKey]
                  )
            else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                // A file untouched today can't contain today's lines.
                guard mtime >= currentDay else { continue }
                added += scanFile(file)
            }
        }

        if added > 0 {
            todayTokens += added
            AgentLog.engine.info("token tracker +\(added) → \(self.todayTokens)")
        }
    }

    /// Returns the tokens found in the bytes appended to `url` since the
    /// last scan, and advances the file cursor past the last complete
    /// line (a trailing partial line is left for the next refresh).
    private func scanFile(_ url: URL) -> Int {
        let cursor = fileCursors[url] ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        // File shrank → rotated/truncated, rescan from the top.
        let start: UInt64 = end < cursor ? 0 : cursor
        guard end > start else { return 0 }

        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let lastNL = text.lastIndex(of: "\n")
        else { return 0 }   // no complete line yet — don't advance cursor

        let complete = text[..<lastNL]
        let consumed = complete.utf8.count + 1   // +1 for the newline
        fileCursors[url] = start + UInt64(consumed)

        var sum = 0
        for line in complete.split(separator: "\n") where !line.isEmpty {
            sum += tokensInLine(String(line))
        }
        return sum
    }

    private func tokensInLine(_ line: String) -> Int {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return 0 }

        // A file modified today can still hold lines from a session
        // that started yesterday — only count today's.
        if let ts = json["timestamp"] as? String, !isToday(ts) { return 0 }

        let input  = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return input + output + cacheCreate + cacheRead
    }

    private func isToday(_ iso: String) -> Bool {
        let date = isoFormatter.date(from: iso)
            ?? isoFormatterNoFraction.date(from: iso)
        guard let date else { return true }   // unparseable → count it
        return Calendar.current.isDate(date, inSameDayAs: currentDay)
    }

    // MARK: - Weekly history

    /// Kick off a fresh 7-day scan. The heavy file walk runs off the
    /// main actor; `weekly` is republished when it completes, so the
    /// history view just observes it. Cheap to call on every history
    /// open — a stale `weekly` shows instantly while the rescan runs.
    func refreshWeekly() {
        let dir = projectsDir
        Task.detached(priority: .utility) {
            let result = Self.scanWeekly(projectsDir: dir)
            await MainActor.run { [weak self] in
                self?.weekly = result.days
                self?.weeklyProjects = result.projects
            }
        }
    }

    /// Pure file walk — safe to run off the main actor. Buckets every
    /// `assistant` line's tokens by the day of its `timestamp`, records
    /// which sessions / projects were active each day, and aggregates
    /// per-project token spend across the window. `days` is exactly 7
    /// entries (oldest → newest), zero-filled; `projects` is sorted by
    /// token spend descending.
    private nonisolated static func scanWeekly(
        projectsDir: URL
    ) -> (days: [DailyActivity], projects: [ProjectSpend]) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(byAdding: .day, value: -6, to: todayStart) else {
            return ([], [])
        }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var buckets: [Date: (tokens: Int, sessions: Set<String>, projects: Set<String>)] = [:]
        var projectTokens: [String: Int] = [:]
        var projectDays: [String: Set<Date>] = [:]

        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return ([], []) }

        for project in projects {
            guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir
            else { continue }
            let projectName = SessionDiscovery.hashToProjectName(project.lastPathComponent)

            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                // A file untouched in the last week can't hold this
                // week's lines.
                guard mtime >= weekStart else { continue }
                let sessionId = file.deletingPathExtension().lastPathComponent
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }

                for line in text.split(separator: "\n") where !line.isEmpty {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          json["type"] as? String == "assistant",
                          let tsString = json["timestamp"] as? String,
                          let ts = isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString)
                    else { continue }

                    let day = cal.startOfDay(for: ts)
                    guard day >= weekStart, day <= todayStart else { continue }

                    let message = json["message"] as? [String: Any]
                    let usage = message?["usage"] as? [String: Any]
                    let tokens = (usage?["input_tokens"] as? Int ?? 0)
                        + (usage?["output_tokens"] as? Int ?? 0)
                        + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                        + (usage?["cache_read_input_tokens"] as? Int ?? 0)

                    var bucket = buckets[day] ?? (0, [], [])
                    bucket.tokens += tokens
                    bucket.sessions.insert(sessionId)
                    bucket.projects.insert(projectName)
                    buckets[day] = bucket

                    projectTokens[projectName, default: 0] += tokens
                    projectDays[projectName, default: []].insert(day)
                }
            }
        }

        let days: [DailyActivity] = (0 ..< 7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let b = buckets[day]
            return DailyActivity(
                day: day,
                tokens: b?.tokens ?? 0,
                agentCount: b?.sessions.count ?? 0,
                projects: Array(b?.projects ?? []).sorted()
            )
        }

        let projectsList: [ProjectSpend] = projectTokens
            .map { name, tokens in
                ProjectSpend(name: name, tokens: tokens, activeDays: projectDays[name]?.count ?? 0)
            }
            .sorted { $0.tokens > $1.tokens }

        return (days, projectsList)
    }
}
