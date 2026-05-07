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
        XCTAssertEqual(session.activity, .idle)
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }
}
