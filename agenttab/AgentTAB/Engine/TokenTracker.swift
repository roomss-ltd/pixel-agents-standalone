// TokenTracker — per-machine daily token-spend counter.
//
// Sums token usage across Claude, Codex, and Devin agents that ran today.
// Claude and Codex usage comes from their native JSONL transcripts; Devin
// usage comes from the CLI's cumulative session metrics database.
//
// Scanning is incremental — each file keeps a byte cursor so a refresh
// only parses bytes appended since the last pass. The counter resets
// automatically when the local date rolls over (it's the source of
// truth recomputed from today's lines, so no persistence is needed).

import Foundation
import Combine

/// One day's slice of agent activity, used by the history dashboard.
struct DailyActivity: Identifiable, Equatable, Codable {
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
struct ProjectSpend: Identifiable, Equatable, Codable {
    var id: String { name }
    let name: String
    let tokens: Int
    let activeDays: Int
}

/// A root project (top-level repo folder) with one or more worktrees
/// nested under it. The history dashboard shows a root row by default
/// and lets the user expand it to see per-worktree totals. `tokens`
/// and `activeDays` are summed/de-duplicated across the worktrees.
struct ProjectGroup: Identifiable, Equatable, Codable {
    var id: String { rootName }
    let rootName: String
    let tokens: Int
    let activeDays: Int
    let worktrees: [ProjectSpend]   // sorted by tokens desc; .name is "root/branch" (or just "root" for single-worktree)
}

struct DevinUsageSnapshot: Decodable, Equatable {
    let id: String
    let workingDirectory: String
    let title: String
    let createdAt: TimeInterval
    let lastActivityAt: TimeInterval
    let tokens: Int
    let activeToolCount: Int
    let activeSubagentCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, tokens
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
        case activeToolCount = "active_tools"
        case activeSubagentCount = "active_subagents"
    }
}

enum DevinUsageReader {
    /// Devin keeps cumulative token counters and tool lifecycle state in its
    /// local CLI database. `-readonly` guarantees polling cannot mutate it.
    nonisolated static func read(databaseURL: URL) -> [DevinUsageSnapshot] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let sql = """
        SELECT s.id, s.working_directory, COALESCE(s.title, '') AS title,
               s.created_at, s.last_activity_at,
               CAST(COALESCE((
                 SELECT SUM(CASE json_extract(metric.value, '$.uid')
                   WHEN 'input_tokens' THEN json_extract(metric.value, '$.kind.CumulativeMetric.value')
                   WHEN 'output_tokens' THEN json_extract(metric.value, '$.kind.CumulativeMetric.value')
                   WHEN 'cached_input_tokens' THEN json_extract(metric.value, '$.kind.CumulativeMetric.value')
                   WHEN 'cache_write_input_tokens' THEN json_extract(metric.value, '$.kind.CumulativeMetric.value')
                   ELSE 0 END)
                 FROM json_each(s.metadata, '$.response_dimensions') AS metric
               ), 0) AS INTEGER) AS tokens,
               (SELECT COUNT(*) FROM tool_call_state AS tool
                WHERE tool.session_id = s.id
                  AND (tool.tool_call_update_json IS NULL
                    OR json_extract(tool.tool_call_update_json, '$.status') NOT IN ('completed', 'failed'))) AS active_tools,
               (SELECT COUNT(*) FROM tool_call_state AS tool
                WHERE tool.session_id = s.id
                  AND tool.tool_call_json LIKE '%inferenceToolName%run_subagent%'
                  AND (tool.tool_call_update_json IS NULL
                    OR json_extract(tool.tool_call_update_json, '$.status') NOT IN ('completed', 'failed'))) AS active_subagents
        FROM sessions AS s
        WHERE COALESCE(s.hidden, 0) = 0;
        """

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, sql]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return (try? JSONDecoder().decode([DevinUsageSnapshot].self, from: data)) ?? []
        } catch {
            return []
        }
    }
}

@MainActor
final class TokenTracker: ObservableObject {
    private struct TodayCache: Codable {
        let day: Date
        let tokens: Int
        let cursors: [String: UInt64]
        let devinCursors: [String: Int]?
    }

    private struct HistoryCache: Codable {
        let daysShort: [DailyActivity]
        let daysMonth: [DailyActivity]
        let daysWindow: [DailyActivity]
        let projectsShort: [ProjectSpend]
        let projectsMonth: [ProjectSpend]
        let projectsWindow: [ProjectSpend]
        let groupsShort: [ProjectGroup]
        let groupsMonth: [ProjectGroup]
        let groupsWindow: [ProjectGroup]
    }

    private struct UsageLedger: Codable {
        var days: [String: LedgerDay] = [:]
    }

    private struct LedgerDay: Codable {
        var tokens = 0
        var sessionIds: Set<String> = []
        var projectTokens: [String: Int] = [:]
    }

    nonisolated private static let defaultProjectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    nonisolated private static let defaultCodexSessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")
    nonisolated private static let defaultDevinDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/devin/cli/sessions.db")
    nonisolated private static let defaultCacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AgentTAB/token-tracker-today.json")
    nonisolated private static let defaultLedgerURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AgentTAB/provider-usage-ledger.json")
    nonisolated private static let defaultHistoryCacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AgentTAB/token-history.json")

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

    /// Full-history scans walk every Claude/Codex transcript in the window.
    /// Expose their lifecycle so the dashboard never presents temporary zeroes
    /// as finished data while that background work is still running.
    @Published private(set) var isHistoryLoading = false
    @Published private(set) var historyScanProgress: Double = 0

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
    private let codexSessionsDir: URL?
    private let devinDatabaseURL: URL?
    private let cacheURL: URL?
    private let ledgerURL: URL?
    private let historyCacheURL: URL?
    private var timer: AnyCancellable?
    private var usageLedger = UsageLedger()

    /// Compact human formatting: 1_234 → "1.2K", 5_000_000 → "5.0M",
    /// 2_000_000_000 → "2.00B", 3_000_000_000_000 → "3.00T".
    static func format(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000_000 { return String(format: "%.2fT", d / 1_000_000_000_000) }
        if d >= 1_000_000_000     { return String(format: "%.2fB", d / 1_000_000_000) }
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
    private var devinCursors: [String: Int] = [:]
    private var codexUsageRecordFiles: Set<URL> = []

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

    init(
        projectsDir: URL = TokenTracker.defaultProjectsDir,
        cacheURL: URL? = nil,
        codexSessionsDir: URL? = nil,
        devinDatabaseURL: URL? = nil,
        ledgerURL: URL? = nil,
        historyCacheURL: URL? = nil
    ) {
        self.projectsDir = projectsDir
        self.codexSessionsDir = codexSessionsDir ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultCodexSessionsDir
                : nil
        )
        self.devinDatabaseURL = devinDatabaseURL ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultDevinDatabaseURL
                : nil
        )
        self.cacheURL = cacheURL ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultCacheURL
                : nil
        )
        self.ledgerURL = ledgerURL ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultLedgerURL
                : nil
        )
        self.historyCacheURL = historyCacheURL ?? (
            projectsDir.standardizedFileURL == Self.defaultProjectsDir.standardizedFileURL
                ? Self.defaultHistoryCacheURL
                : nil
        )
        restoreLedger()
        restoreCache()
        restoreHistoryCache()
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
            devinCursors.removeAll()
            todayTokens = 0
            AgentLog.engine.info("token tracker reset for new day")
        }

        var added = 0
        for source in Self.usageFiles(
            projectsDir: projectsDir,
            codexSessionsDir: codexSessionsDir,
            modifiedSince: currentDay
        ) {
            added += scanFile(source)
        }

        if let devinDatabaseURL {
            for snapshot in DevinUsageReader.read(databaseURL: devinDatabaseURL) {
                let delta: Int
                if let previous = devinCursors[snapshot.id] {
                    delta = max(0, snapshot.tokens - previous)
                } else if snapshot.createdAt >= currentDay.timeIntervalSince1970 {
                    // Count all of a session created today. For an older
                    // running session, first sight establishes a baseline.
                    delta = snapshot.tokens
                } else {
                    delta = 0
                }
                added += delta
                recordDevinUsage(snapshot, tokens: delta)
                devinCursors[snapshot.id] = snapshot.tokens
            }
        }

        if added > 0 {
            todayTokens += added
            AgentLog.engine.info("token tracker +\(added) → \(self.todayTokens)")
        }
        persistCache()
        persistLedger()
    }

    private func recordDevinUsage(_ snapshot: DevinUsageSnapshot, tokens: Int) {
        guard tokens > 0 else { return }
        let key = Self.dayKey(currentDay)
        var day = usageLedger.days[key] ?? LedgerDay()
        day.tokens += tokens
        day.sessionIds.insert(snapshot.id)
        day.projectTokens[SessionDiscovery.pathToProjectName(snapshot.workingDirectory), default: 0] += tokens
        usageLedger.days[key] = day
    }

    private func persistLedger() {
        guard let ledgerURL,
              let data = try? JSONEncoder().encode(usageLedger)
        else { return }
        try? FileManager.default.createDirectory(
            at: ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: ledgerURL, options: .atomic)
    }

    private func restoreLedger() {
        guard let ledgerURL,
              let data = try? Data(contentsOf: ledgerURL),
              let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data)
        else { return }
        usageLedger = ledger
    }

    /// Persist the daily total and per-file byte cursors so relaunching the
    /// menu-bar app does not reparse hundreds of megabytes of today's logs.
    private func persistCache() {
        guard let cacheURL else { return }
        let cache = TodayCache(
            day: currentDay,
            tokens: todayTokens,
            cursors: Dictionary(uniqueKeysWithValues: fileCursors.map { ($0.key.path, $0.value) }),
            devinCursors: devinCursors
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func restoreCache() {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(TodayCache.self, from: data),
              Calendar.current.isDate(cache.day, inSameDayAs: currentDay)
        else { return }
        todayTokens = cache.tokens
        fileCursors = Dictionary(uniqueKeysWithValues: cache.cursors.map {
            (URL(fileURLWithPath: $0.key), $0.value)
        })
        devinCursors = cache.devinCursors ?? [:]
    }

    private func persistHistoryCache() {
        guard let historyCacheURL else { return }
        let cache = HistoryCache(
            daysShort: daysShort,
            daysMonth: daysMonth,
            daysWindow: daysWindow,
            projectsShort: projectsShort,
            projectsMonth: projectsMonth,
            projectsWindow: projectsWindow,
            groupsShort: groupsShort,
            groupsMonth: groupsMonth,
            groupsWindow: groupsWindow
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: historyCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: historyCacheURL, options: .atomic)
    }

    private func restoreHistoryCache() {
        guard let historyCacheURL,
              let data = try? Data(contentsOf: historyCacheURL),
              let cache = try? JSONDecoder().decode(HistoryCache.self, from: data)
        else { return }
        daysShort = cache.daysShort
        daysMonth = cache.daysMonth
        daysWindow = cache.daysWindow
        projectsShort = cache.projectsShort
        projectsMonth = cache.projectsMonth
        projectsWindow = cache.projectsWindow
        groupsShort = cache.groupsShort
        groupsMonth = cache.groupsMonth
        groupsWindow = cache.groupsWindow
    }

    /// Returns the tokens found in the bytes appended to `url` since the
    /// last scan, and advances the file cursor past the last complete
    /// line (a trailing partial line is left for the next refresh).
    private func scanFile(_ source: UsageFile) -> Int {
        let url = source.url
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

        if source.provider == .codex,
           Self.containsCodexUsageRecords(String(complete)) {
            codexUsageRecordFiles.insert(url)
        }
        let includeLegacyCodexEvents = source.provider == .codex
            && !codexUsageRecordFiles.contains(url)

        var sum = 0
        for line in complete.split(separator: "\n") where !line.isEmpty {
            sum += tokensInLine(String(line), includeLegacyCodexEvents: includeLegacyCodexEvents)
        }
        return sum
    }

    private func tokensInLine(_ line: String, includeLegacyCodexEvents: Bool = false) -> Int {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }

        // A file modified today can still hold lines from a session
        // that started yesterday — only count today's.
        if let ts = json["timestamp"] as? String, !isToday(ts) { return 0 }

        return Self.tokenCount(in: json, includeLegacyCodexEvents: includeLegacyCodexEvents) ?? 0
    }

    /// Claude reports cache tokens alongside uncached input, so all four
    /// fields are additive. Codex's `total_tokens` already includes input and
    /// output (cached and reasoning values are breakdowns), so count it once.
    nonisolated private static func tokenCount(
        in json: [String: Any],
        includeLegacyCodexEvents: Bool = false
    ) -> Int? {
        switch json["type"] as? String {
        case "assistant":
            let message = json["message"] as? [String: Any]
            let usage = message?["usage"] as? [String: Any]
            return (usage?["input_tokens"] as? Int ?? 0)
                + (usage?["output_tokens"] as? Int ?? 0)
                + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                + (usage?["cache_read_input_tokens"] as? Int ?? 0)
        case "token_usage_record":
            let payload = json["payload"] as? [String: Any]
            let usage = payload?["usage"] as? [String: Any]
            if let total = usage?["total_tokens"] as? Int { return total }
            return (usage?["input_tokens"] as? Int ?? 0)
                + (usage?["output_tokens"] as? Int ?? 0)
        case "event_msg":
            guard includeLegacyCodexEvents,
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["last_token_usage"] as? [String: Any]
            else { return nil }
            if let total = usage["total_tokens"] as? Int { return total }
            return (usage["input_tokens"] as? Int ?? 0)
                + (usage["output_tokens"] as? Int ?? 0)
        default:
            return nil
        }
    }

    /// Modern Codex mirrors each response into both `event_msg/token_count`
    /// and `token_usage_record`. Prefer the latter whenever it is present in
    /// a file; older transcripts only have the event form.
    nonisolated private static func containsCodexUsageRecords(_ text: String) -> Bool {
        text.contains(#""type":"token_usage_record""#)
            || text.contains(#""type": "token_usage_record""#)
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
        guard !isHistoryLoading else { return }
        isHistoryLoading = true
        historyScanProgress = 0

        let dir = projectsDir
        let codexDir = codexSessionsDir
        let ledger = usageLedger
        let reportProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.historyScanProgress = progress
            }
        }
        Task.detached(priority: .utility) {
            let result = Self.scanRanges(
                projectsDir: dir,
                codexSessionsDir: codexDir,
                providerLedger: ledger,
                progress: reportProgress
            )
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
                self?.historyScanProgress = 1
                self?.isHistoryLoading = false
                self?.persistHistoryCache()
            }
        }
    }

    /// Pure file walk over the widest window (364 days). Records every
    /// assistant line's tokens keyed by (day, project, session) so we can
    /// derive per-range day buckets AND per-range per-project rollups
    /// (both flat-by-worktree and grouped-by-root) from a single pass.
    private nonisolated static func scanRanges(
        projectsDir: URL,
        codexSessionsDir: URL? = nil,
        providerLedger: UsageLedger = UsageLedger(),
        progress: (@Sendable (Double) -> Void)? = nil
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

        let sources = usageFiles(
            projectsDir: projectsDir,
            codexSessionsDir: codexSessionsDir,
            modifiedSince: windowStart
        )
        progress?(sources.isEmpty ? 1 : 0.02)
        let progressStep = max(1, sources.count / 100)

        for (sourceIndex, source) in sources.enumerated() {
            let file = source.url
            let projectName = source.projectName
            let sessionId = file.deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let includeLegacyCodexEvents = source.provider == .codex
                && !containsCodexUsageRecords(text)

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

                    // Tokens: Claude assistant usage or Codex's additive
                    // per-response token_usage_record.
                    guard let tokens = tokenCount(
                        in: json,
                        includeLegacyCodexEvents: includeLegacyCodexEvents
                    ) else { continue }

                    dayTokens[day, default: 0] += tokens
                    daySessions[day, default: []].insert(sessionId)
                    dayProjects[day, default: []].insert(projectName)
                    dayProjectTokens[day, default: [:]][projectName, default: 0] += tokens
            }

            let completed = sourceIndex + 1
            if completed == sources.count || completed.isMultiple(of: progressStep) {
                progress?(0.02 + (Double(completed) / Double(sources.count)) * 0.98)
            }
        }

        for (key, entry) in providerLedger.days {
            guard let day = day(fromKey: key), day >= windowStart, day <= todayStart else { continue }
            dayTokens[day, default: 0] += entry.tokens
            daySessions[day, default: []].formUnion(entry.sessionIds.map { "devin:\($0)" })
            dayProjects[day, default: []].formUnion(entry.projectTokens.keys)
            for (project, tokens) in entry.projectTokens {
                dayProjectTokens[day, default: [:]][project, default: 0] += tokens
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

    private enum UsageProvider {
        case claude, codex
    }

    private struct UsageFile {
        let url: URL
        let projectName: String
        let provider: UsageProvider
    }

    private nonisolated static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private nonisolated static func day(fromKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key).map { Calendar.current.startOfDay(for: $0) }
    }

    private nonisolated static func usageFiles(
        projectsDir: URL,
        codexSessionsDir: URL?,
        modifiedSince: Date
    ) -> [UsageFile] {
        let fm = FileManager.default
        var result: [UsageFile] = []

        let projects = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            guard (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let projectName = SessionDiscovery.hashToProjectName(project.lastPathComponent)
            guard let enumerator = fm.enumerator(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            // Claude stores child-agent transcripts below
            // `<parent-session>/subagents/`; recurse so their spend is part of
            // the same project total as the pane that spawned them.
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      (values?.contentModificationDate ?? .distantPast) >= modifiedSince
                else { continue }
                result.append(UsageFile(url: file, projectName: projectName, provider: .claude))
            }
        }

        if let codexSessionsDir,
           let enumerator = fm.enumerator(
                at: codexSessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
           ) {
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      (values?.contentModificationDate ?? .distantPast) >= modifiedSince
                else { continue }
                result.append(UsageFile(url: file, projectName: codexProjectName(for: file), provider: .codex))
            }
        }
        return result
    }

    private nonisolated static func codexProjectName(for file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return file.deletingLastPathComponent().lastPathComponent
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 128 * 1024)
        guard let text = String(data: data, encoding: .utf8) else {
            return file.deletingLastPathComponent().lastPathComponent
        }
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "session_meta",
                  let payload = json["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String
            else { continue }
            return SessionDiscovery.pathToProjectName(cwd)
        }
        return file.deletingLastPathComponent().lastPathComponent
    }
}
