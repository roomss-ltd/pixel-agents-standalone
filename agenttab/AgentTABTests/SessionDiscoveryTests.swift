import XCTest
@testable import AgentTAB

final class SessionDiscoveryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testExtractsRepoNameFromSimpleProject() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo")
        XCTAssertEqual(result, "my-repo")
    }

    func testExtractsRepoSlashBranchFromWorktree() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo--worktrees-feat-x")
        XCTAssertEqual(result, "my-repo/feat-x")
    }

    func testFallsBackToLastSegmentIfDesktopMissing() {
        let result = SessionDiscovery.hashToProjectName("foo-bar-baz")
        XCTAssertEqual(result, "baz")
    }

    func testExtractsProjectFromNativeWorkingDirectory() {
        XCTAssertEqual(SessionDiscovery.pathToProjectName("/Users/x/Desktop/repo"), "repo")
        XCTAssertEqual(
            SessionDiscovery.pathToProjectName("/Users/x/Desktop/repo/.worktrees/feature"),
            "repo/feature"
        )
    }

    func testLocatesCodexRolloutBySessionId() throws {
        let claude = tempRoot.appendingPathComponent("claude")
        let codex = tempRoot.appendingPathComponent("codex/2026/09/05")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let file = codex.appendingPathComponent("rollout-2026-09-05T12-00-00-codex-id.jsonl")
        try Data("{}\n".utf8).write(to: file)

        let locator = TranscriptLocator(projectsDir: claude, codexSessionsDir: codex.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())

        XCTAssertNotNil(locator.lastWrite(forSessionId: "codex-id"))
        XCTAssertEqual(locator.agentKind(forSessionId: "codex-id"), .codex)
    }

    func testCountsOnlyRunningCodexDescendantsAtTheRoot() throws {
        let codex = tempRoot.appendingPathComponent("codex/2026/09/05")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)

        func write(_ id: String, parent: String?, lifecycle: String) throws {
            let source: [String: Any] = parent.map {
                ["subagent": ["thread_spawn": ["parent_thread_id": $0]]]
            } ?? [:]
            let meta: [String: Any] = [
                "type": "session_meta",
                "payload": ["id": id, "source": source],
            ]
            let event: [String: Any] = [
                "type": "event_msg",
                "payload": ["type": lifecycle],
            ]
            let data = try JSONSerialization.data(withJSONObject: meta)
                + Data("\n".utf8)
                + JSONSerialization.data(withJSONObject: event)
                + Data("\n".utf8)
            try data.write(to: codex.appendingPathComponent("rollout-\(id).jsonl"))
        }

        try write("root", parent: nil, lifecycle: "task_started")
        try write("child", parent: "root", lifecycle: "task_started")
        try write("grandchild", parent: "child", lifecycle: "task_started")
        try write("finished", parent: "root", lifecycle: "task_complete")

        let counts = CodexSubagentScanner.activeCounts(sessionsDir: tempRoot.appendingPathComponent("codex"))

        XCTAssertEqual(counts["root"], 2)
        XCTAssertEqual(counts["child"], 1)
        XCTAssertNil(counts["finished"])
    }
}
