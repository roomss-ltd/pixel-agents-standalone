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

    /// Which tail-window of the 119-day history to expose.
    enum HistoryRange {
        case week, month, window
        var days: Int { self == .week ? 7 : self == .month ? 30 : 119 }
    }

    /// Per-range day buckets, populated on demand by `refreshHistory()`.
    /// Each array is exactly `range.days` entries, oldest first, including
    /// zero days.
    @Published private(set) var daysShort:  [DailyActivity] = []
    @Published private(set) var daysMonth:  [DailyActivity] = []
    @Published private(set) var daysWindow: [DailyActivity] = []

    /// Per-range project rollups, sorted by token spend descending.
    /// Populated alongside the matching `days*` array.
    @Published private(set) var projectsShort:  [ProjectSpend] = []
    @Published private(set) var projectsMonth:  [ProjectSpend] = []
    @Published private(set) var projectsWindow: [ProjectSpend] = []

    func days(for range: HistoryRange) -> [DailyActivity] {
        switch range {
        case .week:   return daysShort
        case .month:  return daysMonth
        case .window: return daysWindow
        }
    }

    func projects(for range: HistoryRange) -> [ProjectSpend] {
        switch range {
        case .week:   return projectsShort
        case .month:  return projectsMonth
        case .window: return projectsWindow
        }
    }

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

    // MARK: - Ranged history

    /// Kick off a fresh ranged scan covering the widest window (119d).
    /// Cheap to call on every history open — stale buckets stay visible
    /// while the rescan runs.
    func refreshHistory() {
        let dir = projectsDir
        Task.detached(priority: .utility) {
            let result = Self.scanRanges(projectsDir: dir)
            await MainActor.run { [weak self] in
                self?.daysShort      = result.short.days
                self?.daysMonth      = result.month.days
                self?.daysWindow     = result.window.days
                self?.projectsShort  = result.short.projects
                self?.projectsMonth  = result.month.projects
                self?.projectsWindow = result.window.projects
            }
        }
    }

    /// Pure file walk over the widest window (119 days). Records every
    /// assistant line's tokens keyed by (day, project, session) so we can
    /// derive per-range day buckets AND per-range per-project rollups
    /// from a single pass.
    private nonisolated static func scanRanges(
        projectsDir: URL
    ) -> (
        short:  (days: [DailyActivity], projects: [ProjectSpend]),
        month:  (days: [DailyActivity], projects: [ProjectSpend]),
        window: (days: [DailyActivity], projects: [ProjectSpend])
    ) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -118, to: todayStart) else {
            return (([], []), ([], []), ([], []))
        }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        // Per-day total tokens (across all projects) and the set of sessions
        // active that day — used to build DailyActivity.
        var dayTokens:   [Date: Int]         = [:]
        var daySessions: [Date: Set<String>] = [:]
        var dayProjects: [Date: Set<String>] = [:]
        // Per (day, project) tokens — used to build per-range ProjectSpend
        // without a second walk.
        var dayProjectTokens: [Date: [String: Int]] = [:]

        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return (([], []), ([], []), ([], [])) }

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
                // A file untouched in the window can't hold a window line.
                guard mtime >= windowStart else { continue }
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
                    guard day >= windowStart, day <= todayStart else { continue }

                    let message = json["message"] as? [String: Any]
                    let usage = message?["usage"] as? [String: Any]
                    let tokens = (usage?["input_tokens"] as? Int ?? 0)
                        + (usage?["output_tokens"] as? Int ?? 0)
                        + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                        + (usage?["cache_read_input_tokens"] as? Int ?? 0)

                    dayTokens[day, default: 0] += tokens
                    daySessions[day, default: []].insert(sessionId)
                    dayProjects[day, default: []].insert(projectName)
                    dayProjectTokens[day, default: [:]][projectName, default: 0] += tokens
                }
            }
        }

        func slice(daysBack: Int) -> (days: [DailyActivity], projects: [ProjectSpend]) {
            guard let start = cal.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) else {
                return ([], [])
            }
            let days: [DailyActivity] = (0 ..< daysBack).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
                return DailyActivity(
                    day: day,
                    tokens: dayTokens[day] ?? 0,
                    agentCount: daySessions[day]?.count ?? 0,
                    projects: Array(dayProjects[day] ?? []).sorted()
                )
            }

            var totals: [String: Int]           = [:]
            var activeDays: [String: Set<Date>] = [:]
            for day in days where day.tokens > 0 {
                if let perProject = dayProjectTokens[day.day] {
                    for (name, tokens) in perProject {
                        totals[name, default: 0] += tokens
                        activeDays[name, default: []].insert(day.day)
                    }
                }
            }
            let projectList = totals
                .map { name, t in ProjectSpend(name: name, tokens: t, activeDays: activeDays[name]?.count ?? 0) }
                .sorted { $0.tokens > $1.tokens }

            return (days, projectList)
        }

        return (
            short:  slice(daysBack: 7),
            month:  slice(daysBack: 30),
            window: slice(daysBack: 119)
        )
    }
}
