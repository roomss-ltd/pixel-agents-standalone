import XCTest
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

    /// Wait for the detached scan in `refreshHistory()` to publish.
    private func waitForScan(_ tracker: TokenTracker) async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        _ = tracker.days(for: .week)
    }

    func testRangedHistoryBucketsByRange() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, input: 1_000)
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 5, input: 2_000)
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 40, output: 5_000)
        // Outside the 119-day window — must be excluded from every range.
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 200, output: 9_999)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let week  = tracker.days(for: .week)
        let month = tracker.days(for: .month)
        let win   = tracker.days(for: .window)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(win.count, 119)

        // Today + 5-days-ago = 3_000 tokens in week range.
        XCTAssertEqual(week.reduce(0) { $0 + $1.tokens }, 3_000)
        // Month adds nothing new (40-days-ago still outside).
        XCTAssertEqual(month.reduce(0) { $0 + $1.tokens }, 3_000)
        // Window picks up the 40-days-ago line.
        XCTAssertEqual(win.reduce(0) { $0 + $1.tokens }, 8_000)
        // 200-days-ago line excluded.
        XCTAssertFalse(win.contains { $0.tokens == 9_999 })
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
}
