import XCTest
import Combine
@testable import AgentTAB

@MainActor
final class TokenTrackerHistoryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tt-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Write one assistant line into `<projectsDir>/<project>/<session>.jsonl`
    /// dated `daysAgo`, with the given token totals.
    private func writeAssistantLine(
        project: String,
        session: String,
        daysAgo: Int,
        input: Int = 0, output: Int = 0, cacheCreate: Int = 0, cacheRead: Int = 0
    ) throws {
        let projectDir = tempRoot.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")
        let todayStart = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: todayStart)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: day)
        let line: [String: Any] = [
            "type": "assistant",
            "timestamp": ts,
            "message": [
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreate,
                    "cache_read_input_tokens": cacheRead,
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: line)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: file.path) {
            handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
        }
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
        try handle.close()
    }

    private func writeCodexUsageLine(
        root: URL? = nil,
        project: String,
        session: String,
        daysAgo: Int,
        total: Int
    ) throws {
        let projectDir = (root ?? tempRoot).appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")
        let todayStart = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: todayStart)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line: [String: Any] = [
            "type": "token_usage_record",
            "timestamp": iso.string(from: day),
            "payload": [
                "session_id": session,
                "usage": [
                    "input_tokens": total - 25,
                    "cached_input_tokens": total - 50,
                    "output_tokens": 25,
                    "reasoning_output_tokens": 10,
                    "total_tokens": total,
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: line)
        try append(data: data, to: file)
    }

    /// Codex transcripts written before `token_usage_record` was added store
    /// the same per-response total in `event_msg.payload.info.last_token_usage`.
    private func writeLegacyCodexUsageLine(
        root: URL? = nil,
        project: String,
        session: String,
        daysAgo: Int,
        total: Int
    ) throws {
        let projectDir = (root ?? tempRoot).appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")
        let todayStart = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: todayStart)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line: [String: Any] = [
            "type": "event_msg",
            "timestamp": iso.string(from: day),
            "payload": [
                "type": "token_count",
                "info": ["last_token_usage": ["total_tokens": total]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: line)
        try append(data: data, to: file)
    }

    private func append(data: Data, to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        handle.write(data)
        handle.write(Data("\n".utf8))
        try handle.close()
    }

    private func writeDevinDatabase(_ database: URL, input: Int, output: Int, cached: Int) throws {
        let created = Int(Date().timeIntervalSince1970)
        let metadata = #"{"response_dimensions":[{"uid":"input_tokens","kind":{"CumulativeMetric":{"value":INPUT}}},{"uid":"output_tokens","kind":{"CumulativeMetric":{"value":OUTPUT}}},{"uid":"cached_input_tokens","kind":{"CumulativeMetric":{"value":CACHED}}}]}"#
            .replacingOccurrences(of: "INPUT", with: "\(input)")
            .replacingOccurrences(of: "OUTPUT", with: "\(output)")
            .replacingOccurrences(of: "CACHED", with: "\(cached)")
        let sql = """
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, working_directory TEXT, created_at INTEGER,
          last_activity_at INTEGER, title TEXT, hidden INTEGER, metadata TEXT
        );
        CREATE TABLE IF NOT EXISTS tool_call_state (
          session_id TEXT, tool_call_id TEXT, tool_call_json TEXT, tool_call_update_json TEXT
        );
        INSERT OR REPLACE INTO sessions VALUES (
          'devin-test', '/tmp/devin-repo', \(created), \(created), 'Fix dashboard', 0, '\(metadata)'
        );
        DELETE FROM tool_call_state;
        INSERT INTO tool_call_state VALUES (
          'devin-test', 'run_subagent:1',
          '{"_meta":{"cognition.ai/inferenceToolName":"run_subagent"}}', NULL
        );
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    /// Wait for the detached scan in `refreshHistory()` to publish.
    /// Subscribes to the window publisher and fulfills on the first
    /// non-empty emission — deterministic and fast on the happy path,
    /// versus a fixed sleep that flakes on slow CI.
    private func waitForScan(_ tracker: TokenTracker) async {
        let exp = XCTestExpectation(description: "ranged history published")
        let cancellable = tracker.$daysWindow
            .dropFirst()
            .sink { _ in exp.fulfill() }
        await fulfillment(of: [exp], timeout: 2.0)
        cancellable.cancel()
    }

    func testRangedHistoryBucketsByRange() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, input: 1_000)
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 5, input: 2_000)
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 40, output: 5_000)
        // Outside the 364-day window — must be excluded from every range.
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 400, output: 9_999)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let week  = tracker.days(for: .week)
        let month = tracker.days(for: .month)
        let win   = tracker.days(for: .window)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(win.count, 364)

        // Today + 5-days-ago = 3_000 tokens in week range.
        XCTAssertEqual(week.reduce(0) { $0 + $1.tokens }, 3_000)
        // Month adds nothing new (40-days-ago still outside).
        XCTAssertEqual(month.reduce(0) { $0 + $1.tokens }, 3_000)
        // Window picks up the 40-days-ago line.
        XCTAssertEqual(win.reduce(0) { $0 + $1.tokens }, 8_000)
        // 400-days-ago line excluded.
        XCTAssertFalse(win.contains { $0.tokens == 9_999 })
    }

    func testHistoryLoadingStateCompletesWithMeasuredProgress() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, input: 1_000)
        let tracker = TokenTracker(projectsDir: tempRoot)

        XCTAssertFalse(tracker.isHistoryLoading)
        XCTAssertEqual(tracker.historyScanProgress, 0)

        tracker.refreshHistory()
        XCTAssertTrue(tracker.isHistoryLoading)
        await waitForScan(tracker)

        XCTAssertFalse(tracker.isHistoryLoading)
        XCTAssertEqual(tracker.historyScanProgress, 1)
    }

    func testCompletedHistoryIsRestoredImmediatelyOnRelaunch() async throws {
        let historyCache = tempRoot.appendingPathComponent("history.json")
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 40, input: 2_500)

        let first = TokenTracker(projectsDir: tempRoot, historyCacheURL: historyCache)
        first.refreshHistory()
        await waitForScan(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyCache.path))

        let restored = TokenTracker(projectsDir: tempRoot, historyCacheURL: historyCache)
        XCTAssertEqual(restored.days(for: .window).count, 364)
        XCTAssertEqual(restored.days(for: .window).reduce(0) { $0 + $1.tokens }, 2_500)
        XCTAssertFalse(restored.isHistoryLoading)
    }

    func testLegacyCodexHistoryFillsOlderDaysWithoutDoubleCountingModernRecords() async throws {
        let claudeRoot = tempRoot.appendingPathComponent("claude")
        let codexRoot = tempRoot.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)

        // The user's April-June transcripts use this legacy event format.
        try writeLegacyCodexUsageLine(
            root: codexRoot,
            project: "2026/05/08",
            session: "legacy",
            daysAgo: 120,
            total: 1_500
        )

        // Current Codex writes both representations for one response. When a
        // file has additive records, the legacy mirror must be ignored.
        try writeLegacyCodexUsageLine(
            root: codexRoot,
            project: "2026/09/03",
            session: "modern",
            daysAgo: 2,
            total: 700
        )
        try writeCodexUsageLine(
            root: codexRoot,
            project: "2026/09/03",
            session: "modern",
            daysAgo: 2,
            total: 700
        )

        let tracker = TokenTracker(projectsDir: claudeRoot, codexSessionsDir: codexRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let window = tracker.days(for: .window)
        XCTAssertEqual(window.first(where: { Calendar.current.isDate($0.day, inSameDayAs: Calendar.current.date(byAdding: .day, value: -120, to: Date())!) })?.tokens, 1_500)
        XCTAssertEqual(window.first(where: { Calendar.current.isDate($0.day, inSameDayAs: Calendar.current.date(byAdding: .day, value: -2, to: Date())!) })?.tokens, 700)
    }

    func testProjectGroupsByRoot() async throws {
        // Two worktrees of repoA (plain root + a feat branch) plus a
        // single-worktree repoB — all on day 1 so they fall inside .week.
        // Project hashes need a "Desktop" segment for SessionDiscovery's
        // root/worktree splitter to fire.
        try writeAssistantLine(project: "-Users-x-Desktop-repoA", session: "s1",
                               daysAgo: 1, input: 1_000)
        try writeAssistantLine(project: "-Users-x-Desktop-repoA--worktrees-feat-foo", session: "s2",
                               daysAgo: 1, input: 2_500)
        try writeAssistantLine(project: "-Users-x-Desktop-repoB", session: "s3",
                               daysAgo: 1, input: 800)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let groups = tracker.projectGroups(for: .week)
        XCTAssertEqual(groups.count, 2)

        // Sorted by tokens desc: repoA (3500) before repoB (800).
        XCTAssertEqual(groups[0].rootName, "repoA")
        XCTAssertEqual(groups[0].tokens, 3_500)
        XCTAssertEqual(groups[0].worktrees.count, 2)
        // Sorted by tokens desc within the group.
        XCTAssertEqual(groups[0].worktrees[0].name, "repoA/feat-foo")
        XCTAssertEqual(groups[0].worktrees[0].tokens, 2_500)
        XCTAssertEqual(groups[0].worktrees[1].name, "repoA")
        XCTAssertEqual(groups[0].worktrees[1].tokens, 1_000)
        // Active days de-duplicated across worktrees (same day).
        XCTAssertEqual(groups[0].activeDays, 1)

        XCTAssertEqual(groups[1].rootName, "repoB")
        XCTAssertEqual(groups[1].tokens, 800)
        XCTAssertEqual(groups[1].worktrees.count, 1)
        XCTAssertEqual(groups[1].worktrees[0].name, "repoB")
    }

    func testRangedProjectsRollupIsPerRange() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 1, input: 1_000)
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 40, output: 5_000)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let weekProjects   = tracker.projects(for: .week)
        let windowProjects = tracker.projects(for: .window)

        XCTAssertEqual(weekProjects.map(\.name), ["repoA"])
        XCTAssertEqual(Set(windowProjects.map(\.name)), ["repoA", "repoB"])
    }

    func testTodayCacheRestoresTotalAndOnlyScansAppendedBytes() throws {
        let cacheURL = tempRoot.appendingPathComponent("token-cache.json")
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, input: 1_000)

        let first = TokenTracker(projectsDir: tempRoot, cacheURL: cacheURL)
        first.refresh()
        XCTAssertEqual(first.todayTokens, 1_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        let restored = TokenTracker(projectsDir: tempRoot, cacheURL: cacheURL)
        XCTAssertEqual(restored.todayTokens, 1_000)

        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, output: 250)
        restored.refresh()
        XCTAssertEqual(restored.todayTokens, 1_250)
    }

    func testClaudeSubagentTranscriptsContributeToParentProjectSpend() async throws {
        let project = "-Users-x-Desktop-repoA"
        try writeAssistantLine(
            project: project,
            session: "parent",
            daysAgo: 0,
            input: 1_000
        )
        try writeAssistantLine(
            project: project,
            session: "agent-child",
            daysAgo: 0,
            output: 250
        )

        let projectDir = tempRoot.appendingPathComponent(project)
        let childDir = projectDir.appendingPathComponent("parent/subagents")
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: projectDir.appendingPathComponent("agent-child.jsonl"),
            to: childDir.appendingPathComponent("agent-child.jsonl")
        )

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refresh()
        XCTAssertEqual(tracker.todayTokens, 1_250, "parent and Claude subagent spend should both count")

        tracker.refreshHistory()
        await waitForScan(tracker)
        XCTAssertEqual(tracker.days(for: .week).last?.tokens, 1_250)
        XCTAssertEqual(tracker.projects(for: .week).first?.name, "repoA")
    }

    func testCodexUsageRecordsCountTotalTokensWithoutDoubleCountingCachedOrReasoning() async throws {
        let claudeRoot = tempRoot.appendingPathComponent("claude")
        let codexRoot = tempRoot.appendingPathComponent("codex")
        let codexDay = codexRoot.appendingPathComponent("2026/09/05")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try writeCodexUsageLine(
            root: codexDay,
            project: "rollouts",
            session: "codex-parent",
            daysAgo: 0,
            total: 1_250
        )
        try writeCodexUsageLine(
            root: codexDay,
            project: "-Users-x-Desktop-codex-repo",
            session: "codex-subagent",
            daysAgo: 0,
            total: 400
        )

        let tracker = TokenTracker(projectsDir: claudeRoot, codexSessionsDir: codexRoot)
        tracker.refresh()
        XCTAssertEqual(tracker.todayTokens, 1_650, "parent and subagent spend should both count")

        tracker.refreshHistory()
        await waitForScan(tracker)
        XCTAssertEqual(tracker.days(for: .week).last?.tokens, 1_650)
        XCTAssertEqual(tracker.days(for: .week).last?.agentCount, 2)
    }

    func testDevinCumulativeUsageAddsOnlyNewSpend() async throws {
        let database = tempRoot.appendingPathComponent("devin.db")
        let cache = tempRoot.appendingPathComponent("today.json")
        let ledger = tempRoot.appendingPathComponent("ledger.json")
        try writeDevinDatabase(database, input: 100, output: 20, cached: 40)

        let tracker = TokenTracker(
            projectsDir: tempRoot,
            cacheURL: cache,
            devinDatabaseURL: database,
            ledgerURL: ledger
        )
        tracker.refresh()
        XCTAssertEqual(tracker.todayTokens, 160)

        try writeDevinDatabase(database, input: 130, output: 25, cached: 55)
        tracker.refresh()
        XCTAssertEqual(tracker.todayTokens, 210)

        let snapshot = try XCTUnwrap(DevinUsageReader.read(databaseURL: database).first)
        XCTAssertEqual(snapshot.activeSubagentCount, 1)
        XCTAssertEqual(snapshot.title, "Fix dashboard")

        let restored = TokenTracker(
            projectsDir: tempRoot,
            cacheURL: cache,
            devinDatabaseURL: database,
            ledgerURL: ledger
        )
        restored.refresh()
        XCTAssertEqual(restored.todayTokens, 210)
        restored.refreshHistory()
        await waitForScan(restored)
        XCTAssertEqual(restored.days(for: .week).last?.tokens, 210)
        XCTAssertEqual(restored.days(for: .week).last?.agentCount, 1)
        XCTAssertEqual(restored.projects(for: .week).first?.name, "devin-repo")
    }
}
