import XCTest
@testable import AgentTAB

final class TranscriptParserTests: XCTestCase {
    func testParsesToolUseBlock() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/b.swift"}}]}}"#
        let events = parser.parseLine(line, session: &session)
        XCTAssertEqual(events, [.toolStarted(toolId: "t1", status: "Reading b.swift")])
        XCTAssertEqual(session.activity, .tool("Read"))
        XCTAssertEqual(session.activeToolIds, ["t1"])
        XCTAssertEqual(session.currentTool, "Reading b.swift")
    }

    func testParsesToolResult() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolIds = ["t1"]
        session.activity = .tool("Read")

        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#
        let events = parser.parseLine(line, session: &session)
        XCTAssertEqual(events, [.toolCompleted(toolId: "t1")])
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }

    func testIgnoresUserTextPromptByDefault() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        let line = #"{"type":"user","message":{"content":"hello"}}"#
        let events = parser.parseLine(line, session: &session)
        XCTAssertTrue(events.isEmpty)
    }

    func testTurnDurationEndsTurnAndClearsTools() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolIds = ["t1", "t2"]
        session.activity = .thinking

        let line = #"{"type":"system","subtype":"turn_duration"}"#
        let events = parser.parseLine(line, session: &session)
        XCTAssertEqual(events, [.turnEnded])
        XCTAssertEqual(session.activity, .waiting)
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }
}
