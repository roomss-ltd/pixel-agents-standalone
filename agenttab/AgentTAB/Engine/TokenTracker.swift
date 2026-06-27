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

/// One day's slice of agent activity, used by the history dashboard.
struct DailyActivity: Identifiable, Equatable {
    var id: Date { day }
    let day: Date           // start of day
    let tokens: Int         // total tokens spent that day
    let agentCount: Int     // distinct agent sessions active that day
    let projects: [String]  // project names worked on that day
    /// Wall-clock seconds in which *at least one* agent was active — the
    /// union of every agent's active stretches, deduplicated for overlap
    /// and capped at 24h. "How long the day's work actually spanned."
    let unionActiveSeconds: Int
    /// Sum of every agent's active seconds, NOT deduplicated for overlap —
    /// 5 agents each active 10h ⇒ 180_000s (50h). "Total agent-hours."
    let summedActiveSeconds: Int
}

/// A project's total token spend over the active history range —
/// "what the agents were working on."
struct ProjectSpend: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let tokens: Int
    let activeDays: Int
}

/// A root project (top-level repo folder) with one or more worktrees
/// nested under it. The history dashboard shows a root row by default
/// and lets the user expand it to see per-worktree totals. `tokens`
/// and `activeDays` are summed/de-duplicated across the worktrees.
struct ProjectGroup: Identifiable, Equatable {
    var id: String { rootName }
    let rootName: String
    let tokens: Int
    let activeDays: Int
    let worktrees: [ProjectSpend]   // sorted by tokens desc; .name is "root/branch" (or just "root" for single-worktree)
}

@MainActor
final class TokenTracker: ObservableObject {
    /// Total tokens spent across all agents on the local machine today.
    @Published private(set) var todayTokens: Int = 0

    /// Which tail-window of the 364-day history to expose.
    enum HistoryRange {
        case week, month, window
        var days: Int { self == .week ? 7 : self == .month ? 30 : 364 }
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

    /// Per-range project rollups grouped by root folder. Worktrees of
    /// the same repo collapse into a single `ProjectGroup` so the UI
    /// can show one row per repo with an expand affordance.
    @Published private(set) var groupsShort:  [ProjectGroup] = []
    @Published private(set) var groupsMonth:  [ProjectGroup] = []
    @Published private(set) var groupsWindow: [ProjectGroup] = []

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

    func projectGroups(for range: HistoryRange) -> [ProjectGroup] {
        switch range {
        case .week:   return groupsShort
        case .month:  return groupsMonth
        case .window: return groupsWindow
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

    /// Compact duration formatting for the history dashboard:
    /// 0 → "0m", <60s → "<1m", 2_700 → "45m", 29_520 → "8h12m",
    /// 113_040 → "31h24m". Rounds down to the minute — active time is a
    /// timestamp-derived estimate, not a stopwatch.
    static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        if seconds < 60 { return "<1m" }
        let minutes = seconds / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h\(m)m"
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
        // One initial read so the collapsed counter shows a number at launch.
        // The periodic refresh now runs ONLY while the panel is open (see
        // `setActive`) — no perpetual 60s directory scan while collapsed.
        refresh()
    }

    /// Drive the periodic refresh off panel visibility. While the expanded
    /// panel is open we refresh every 60s for a live-ish number; once it
    /// closes the timer stops entirely, so there's zero idle disk scanning.
    func setActive(_ active: Bool) {
        if active {
            refresh()
            guard timer == nil else { return }
            timer = Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        } else {
            timer?.cancel()
            timer = nil
        }
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

    // MARK: - Active-time derivation
    //
    // Per-day active time is reconstructed offline from the JSONL line
    // timestamps alone — no dependency on the live ActivityEngine, which
    // only sees sessions running during the current app launch. For one
    // agent, consecutive timestamped lines closer than `activeIdleGap`
    // form a single continuous active stretch; a longer silence ends it
    // (the agent was idle / the human stepped away). Each stretch is
    // credited at least `activeMinInterval` so a lone message isn't free.
    //
    // `nonisolated` so the off-main `scanRanges` walk can call them.

    /// A silence longer than this (seconds) splits one active stretch from
    /// the next — 5 min spans tool runs + thinking pauses while excluding
    /// genuine walk-away gaps.
    nonisolated static let activeIdleGap: TimeInterval = 300

    /// Floor credited to any single active stretch (seconds), so a stretch
    /// built from one isolated message is worth something, not zero.
    nonisolated static let activeMinInterval: TimeInterval = 30

    /// Sum of stretch lengths WITHOUT merging — each floored at
    /// `activeMinInterval`. Drives the per-agent summed (agent-hours)
    /// metric when applied per session and totalled.
    nonisolated private static func summedSeconds(_ stretches: [(start: Double, end: Double)]) -> Int {
        let total = stretches.reduce(0.0) { $0 + max($1.end - $1.start, activeMinInterval) }
        return Int(total.rounded())
    }

    /// Merge overlapping/touching stretches across all agents, then sum the
    /// merged spans (each floored at `activeMinInterval`), capped at `cap`.
    /// Drives the wall-clock union metric.
    nonisolated private static func unionSeconds(_ stretches: [(start: Double, end: Double)], cap: TimeInterval) -> Int {
        guard !stretches.isEmpty else { return 0 }
        let sorted = stretches.sorted { $0.start < $1.start }
        var merged: [(start: Double, end: Double)] = [sorted[0]]
        for iv in sorted.dropFirst() {
            if iv.start <= merged[merged.count - 1].end {
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, iv.end)
            } else {
                merged.append(iv)
            }
        }
        let total = merged.reduce(0.0) { $0 + max($1.end - $1.start, activeMinInterval) }
        return Int(min(total, cap).rounded())
    }

    // MARK: - Ranged history

    /// Kick off a fresh ranged scan covering the widest window (364d).
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
                self?.groupsShort    = result.short.groups
                self?.groupsMonth    = result.month.groups
                self?.groupsWindow   = result.window.groups
            }
        }
    }

    /// Pure file walk over the widest window (364 days). Records every
    /// assistant line's tokens keyed by (day, project, session) so we can
    /// derive per-range day buckets AND per-range per-project rollups
    /// (both flat-by-worktree and grouped-by-root) from a single pass.
    private nonisolated static func scanRanges(
        projectsDir: URL
    ) -> (
        short:  (days: [DailyActivity], projects: [ProjectSpend], groups: [ProjectGroup]),
        month:  (days: [DailyActivity], projects: [ProjectSpend], groups: [ProjectGroup]),
        window: (days: [DailyActivity], projects: [ProjectSpend], groups: [ProjectGroup])
    ) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -363, to: todayStart) else {
            return (([], [], []), ([], [], []), ([], [], []))
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
        // Per (day, session) active stretches, folded incrementally as the
        // chronological lines of each session file stream past. The last
        // stretch's `end` is the session's last-seen timestamp, so a fresh
        // line either extends it (within the idle gap) or opens a new
        // stretch. Bounded by stretch count, not line count.
        var dayActiveStretches: [Date: [String: [(start: Double, end: Double)]]] = [:]

        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return (([], [], []), ([], [], []), ([], [], [])) }

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
                          let tsString = json["timestamp"] as? String,
                          let ts = isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString)
                    else { continue }

                    let day = cal.startOfDay(for: ts)
                    guard day >= windowStart, day <= todayStart else { continue }

                    // Active time: fold EVERY timestamped line (user /
                    // assistant / system alike — they all carry the agent's
                    // real activity over time) into the session's stretches.
                    let epoch = ts.timeIntervalSince1970
                    var stretches = dayActiveStretches[day]?[sessionId] ?? []
                    if let lastEnd = stretches.last?.end,
                       epoch >= lastEnd,
                       epoch - lastEnd <= Self.activeIdleGap {
                        stretches[stretches.count - 1].end = epoch
                    } else {
                        stretches.append((start: epoch, end: epoch))
                    }
                    dayActiveStretches[day, default: [:]][sessionId] = stretches

                    // Tokens: assistant lines only.
                    guard json["type"] as? String == "assistant" else { continue }
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

        // Collapse the folded stretches into the two per-day metrics:
        // `summed` totals each session's stretches independently (overlap
        // intended); `union` merges all sessions' stretches first (overlap
        // removed), then caps at 24h.
        var dayUnionSeconds:  [Date: Int] = [:]
        var daySummedSeconds: [Date: Int] = [:]
        for (day, sessions) in dayActiveStretches {
            var allStretches: [(start: Double, end: Double)] = []
            var summed = 0
            for (_, stretches) in sessions {
                summed += summedSeconds(stretches)
                allStretches.append(contentsOf: stretches)
            }
            daySummedSeconds[day] = summed
            dayUnionSeconds[day]  = unionSeconds(allStretches, cap: 86_400)
        }

        func slice(daysBack: Int) -> (days: [DailyActivity], projects: [ProjectSpend], groups: [ProjectGroup]) {
            guard let start = cal.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) else {
                return ([], [], [])
            }
            let days: [DailyActivity] = (0 ..< daysBack).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
                return DailyActivity(
                    day: day,
                    tokens: dayTokens[day] ?? 0,
                    agentCount: daySessions[day]?.count ?? 0,
                    projects: Array(dayProjects[day] ?? []).sorted(),
                    unionActiveSeconds: dayUnionSeconds[day] ?? 0,
                    summedActiveSeconds: daySummedSeconds[day] ?? 0
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

            // Roll the per-worktree spend up to the root folder. A name
            // like "repo/feat-x" groups under "repo"; a plain "repo"
            // forms its own single-worktree group.
            var rootTokens:     [String: Int]       = [:]
            var rootActiveDays: [String: Set<Date>] = [:]
            var rootWorktrees:  [String: [ProjectSpend]] = [:]
            for spend in projectList {
                let root: String
                if let slash = spend.name.firstIndex(of: "/") {
                    root = String(spend.name[..<slash])
                } else {
                    root = spend.name
                }
                rootTokens[root, default: 0] += spend.tokens
                rootActiveDays[root, default: []].formUnion(activeDays[spend.name] ?? [])
                rootWorktrees[root, default: []].append(spend)
            }
            let groupList = rootTokens
                .map { root, tokens in
                    let worktrees = (rootWorktrees[root] ?? []).sorted { $0.tokens > $1.tokens }
                    return ProjectGroup(
                        rootName: root,
                        tokens: tokens,
                        activeDays: rootActiveDays[root]?.count ?? 0,
                        worktrees: worktrees
                    )
                }
                .sorted { $0.tokens > $1.tokens }

            return (days, projectList, groupList)
        }

        return (
            short:  slice(daysBack: 7),
            month:  slice(daysBack: 30),
            window: slice(daysBack: 364)
        )
    }
}
