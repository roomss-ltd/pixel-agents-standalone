import XCTest
@testable import AgentTAB

final class HookPayloadTests: XCTestCase {
    func testDecodesPreToolUsePayload() throws {
        let json = #"{"pane_id":42,"session_id":"abc-123","hook_event":"PreToolUse","tool_name":"Bash","term_program":"ghostty"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(payload.paneId, 42)
        XCTAssertEqual(payload.sessionId, "abc-123")
        XCTAssertEqual(payload.hookEvent, "PreToolUse")
        XCTAssertEqual(payload.toolName, "Bash")
        XCTAssertEqual(payload.termProgram, "ghostty")
    }

    func testDecodesWithMissingOptionalFields() throws {
        let json = #"{"pane_id":null,"session_id":"x","hook_event":"Stop"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)
        XCTAssertNil(payload.paneId)
        XCTAssertNil(payload.toolName)
        XCTAssertNil(payload.termProgram)
    }

    func testDecodesNullablePaneIdAsNil() throws {
        let json = #"{"pane_id":null,"session_id":"abc","hook_event":"PreToolUse","term_program":"ghostty"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)
        XCTAssertNil(payload.paneId)
        XCTAssertEqual(payload.sessionId, "abc")
    }
}
