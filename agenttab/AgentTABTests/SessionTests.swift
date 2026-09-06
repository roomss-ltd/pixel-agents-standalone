import XCTest
@testable import AgentTAB

final class SessionTests: XCTestCase {
    func testSessionInitializesWithDefaults() {
        let session = Session(
            claudeSessionId: "abc-123",
            projectName: "my-repo",
            projectPath: "/Users/me/my-repo"
        )
        XCTAssertEqual(session.claudeSessionId, "abc-123")
        XCTAssertEqual(session.agentKind, .claude)
        XCTAssertEqual(session.activity, .idle)
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }

    func testNativeAndTranscriptSubagentsAreCombined() {
        var session = Session(
            claudeSessionId: "abc-123",
            projectName: "my-repo",
            projectPath: "/Users/me/my-repo",
            agentKind: .codex
        )
        session.subagentTools["task"] = ["tool"]
        session.nativeSubagentCount = 2

        XCTAssertEqual(session.activeSubagentCount, 3)
        XCTAssertEqual(session.agentKind.displayName, "Codex")
    }
}
