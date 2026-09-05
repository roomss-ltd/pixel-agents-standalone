import XCTest
@testable import AgentTAB

@MainActor
final class AgentTABTests: XCTestCase {
    func testConnectedClientCountForDetachedSession() {
        XCTAssertEqual(
            ActivityEngine.connectedClientCount(
                from: "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n"
            ),
            0
        )
    }

    func testConnectedClientCountForAttachedSession() {
        XCTAssertEqual(
            ActivityEngine.connectedClientCount(
                from: "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n1 terminal_0 codex\n"
            ),
            1
        )
    }

    func testConnectedClientCountRejectsUnexpectedOutput() {
        XCTAssertNil(ActivityEngine.connectedClientCount(from: "zellij failed\n"))
    }
}
