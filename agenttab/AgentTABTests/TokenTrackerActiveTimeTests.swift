import XCTest
import Combine
@testable import AgentTAB

/// Covers the per-day active-time metrics derived from JSONL timestamps:
/// `unionActiveSeconds` (wall-clock, overlap-deduplicated, ≤24h) and
/// `summedActiveSeconds` (per-agent durations totalled). Both are folded
/// inside the same 364-day walk that already computes token spend, so
/// these exercise the interval reconstruction end-to-end through the
/// published `days(for:)` arrays.
@MainActor
final class TokenTrackerActiveTimeTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tt-active-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Fixtures

    /// Append one JSONL line at `daysAgo` + `secondsIntoDay`. Any `type`
    /// is allowed (only `assistant` lines carry token usage); all
    /// timestamped lines feed active-time reconstruction. Lines for a
    /// given session MUST be written in chronological order — that mirrors
    /// how Claude Code appends to a transcript and is what the scanner's
    /// running-end fold assumes.
    private func writeLine(
        project: String, session: String,
        daysAgo: Int, secondsIntoDay: Int,
        type: String = "assistant",
        input: Int = 0, output: Int = 0, cacheCreate: Int = 0, cacheRead: Int = 0
    ) throws {
        let projectDir = tempRoot.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")

        let cal = Calendar.current
        let dayStart = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        let ts = dayStart.addingTimeInterval(TimeInterval(secondsIntoDay))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var line: [String: Any] = ["type": type, "timestamp": iso.string(from: ts)]
        if type == "assistant" {
            line["message"] = ["usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_creation_input_tokens": cacheCreate,
                "cache_read_input_tokens": cacheRead,
            ]]
        }

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

    private func waitForScan(_ tracker: TokenTracker) async {
        let exp = XCTestExpectation(description: "ranged history published")
        let cancellable = tracker.$daysWindow
            .dropFirst()
            .sink { _ in exp.fulfill() }
        await fulfillment(of: [exp], timeout: 2.0)
        cancellable.cancel()
    }

    private func day(_ tracker: TokenTracker, _ daysAgo: Int) -> DailyActivity? {
        let target = Calendar.current.date(
            byAdding: .day, value: -daysAgo,
            to: Calendar.current.startOfDay(for: Date())
        )!
        return tracker.days(for: .week).first { $0.day == target }
    }

    // MARK: - formatDuration (pure)

    func testFormatDuration() {
        XCTAssertEqual(TokenTracker.formatDuration(0), "0m")
        XCTAssertEqual(TokenTracker.formatDuration(30), "<1m")
        XCTAssertEqual(TokenTracker.formatDuration(59), "<1m")
        XCTAssertEqual(TokenTracker.formatDuration(60), "1m")
        XCTAssertEqual(TokenTracker.formatDuration(2_700), "45m")
        XCTAssertEqual(TokenTracker.formatDuration(3_600), "1h")
        XCTAssertEqual(TokenTracker.formatDuration(29_520), "8h12m")
        XCTAssertEqual(TokenTracker.formatDuration(113_040), "31h24m")
        XCTAssertEqual(TokenTracker.formatDuration(86_400), "24h")
    }

    // MARK: - Interval reconstruction

    /// A lone message has no neighbour to span to, so it is credited the
    /// 30s floor (`activeMinInterval`) rather than zero.
    func testSingleMessageGetsMinimumCredit() async throws {
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_000, input: 100)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let d = try XCTUnwrap(day(tracker, 3))
        XCTAssertEqual(d.unionActiveSeconds, 30)
        XCTAssertEqual(d.summedActiveSeconds, 30)
    }

    /// Two messages 60s apart (< the 5-min idle gap) are one continuous
    /// stretch worth exactly their span.
    func testTwoMessagesWithinGapAreOneStretch() async throws {
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_000, input: 100)
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_060, input: 100)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let d = try XCTUnwrap(day(tracker, 3))
        XCTAssertEqual(d.unionActiveSeconds, 60)
        XCTAssertEqual(d.summedActiveSeconds, 60)
    }

    /// A silence longer than the idle gap (700s > 300s) splits the day
    /// into two stretches — so the 700s gap is NOT counted as active. Both
    /// stretches are single messages, each credited the 30s floor.
    func testGapLongerThanThresholdSplitsStretches() async throws {
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_000, input: 100)
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_700, input: 100)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let d = try XCTUnwrap(day(tracker, 3))
        // Two 30s-floored stretches, NOT one 700s stretch.
        XCTAssertEqual(d.summedActiveSeconds, 60)
        XCTAssertEqual(d.unionActiveSeconds, 60)
    }

    /// Two agents whose stretches overlap: the summed metric counts both
    /// in full (300 + 300 = 600), while the wall-clock union merges the
    /// overlap (3600–4050 = 450). This is the core distinction between the
    /// two metrics.
    func testOverlappingSessionsUnionVsSummed() async throws {
        // Agent A active 3600–3900 (steps of 100s).
        for t in stride(from: 3_600, through: 3_900, by: 100) {
            try writeLine(project: "-Users-x-repoA", session: "sA", daysAgo: 3, secondsIntoDay: t, input: 10)
        }
        // Agent B active 3750–4050, overlapping A.
        for t in stride(from: 3_750, through: 4_050, by: 100) {
            try writeLine(project: "-Users-x-repoA", session: "sB", daysAgo: 3, secondsIntoDay: t, input: 10)
        }

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let d = try XCTUnwrap(day(tracker, 3))
        XCTAssertEqual(d.summedActiveSeconds, 600, "two 300s agents, overlap NOT deduplicated")
        XCTAssertEqual(d.unionActiveSeconds, 450, "overlap merged: 3600–4050")
        XCTAssertEqual(d.agentCount, 2)
        // Invariants that must always hold.
        XCTAssertLessThanOrEqual(d.unionActiveSeconds, d.summedActiveSeconds)
        XCTAssertLessThanOrEqual(d.unionActiveSeconds, 86_400)
    }

    /// Non-assistant lines (user / system) carry no token usage but DO
    /// mark the agent as active — so they extend active time without
    /// touching the token total.
    func testNonAssistantLinesFeedTimeNotTokens() async throws {
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_000, type: "assistant", input: 500)
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_060, type: "user")

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let d = try XCTUnwrap(day(tracker, 3))
        XCTAssertEqual(d.tokens, 500, "only the assistant line contributes tokens")
        XCTAssertEqual(d.unionActiveSeconds, 60, "the user line extends the active stretch")
        XCTAssertEqual(d.summedActiveSeconds, 60)
    }

    /// A day with no agent activity reports zero for both metrics.
    func testEmptyDayIsZero() async throws {
        try writeLine(project: "-Users-x-repoA", session: "s1", daysAgo: 3, secondsIntoDay: 1_000, input: 100)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        // daysAgo 2 had nothing written.
        let empty = try XCTUnwrap(day(tracker, 2))
        XCTAssertEqual(empty.unionActiveSeconds, 0)
        XCTAssertEqual(empty.summedActiveSeconds, 0)
        XCTAssertEqual(empty.tokens, 0)
    }
}
