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

    func testProgressRecordTracksSubagentTool() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolIds = ["parent_t"]

        let nameMap: [String: String] = ["parent_t": "Task"]

        let line = #"{"type":"progress","parentToolUseID":"parent_t","data":{"type":"agent_progress","message":{"type":"assistant","message":{"content":[{"type":"tool_use","id":"sub_t","name":"Bash","input":{"command":"ls"}}]}}}}"#

        let events = parser.parseLineWithToolNames(line, session: &session, parentNames: nameMap)
        XCTAssertEqual(events, [.subagentToolStarted(parentId: "parent_t", toolId: "sub_t", status: "Running: ls")])
        XCTAssertEqual(session.subagentTools["parent_t"], ["sub_t"])
    }

    func testProgressIgnoredWhenParentIsNotTaskOrAgent() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        let nameMap: [String: String] = ["parent_t": "Bash"]

        let line = #"{"type":"progress","parentToolUseID":"parent_t","data":{"type":"agent_progress","message":{"type":"assistant","message":{"content":[{"type":"tool_use","id":"sub_t","name":"Read","input":{"file_path":"/x"}}]}}}}"#

        let events = parser.parseLineWithToolNames(line, session: &session, parentNames: nameMap)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(session.subagentTools["parent_t"])
    }

    func testProgressBashOrMcpProgressEmitsNothing() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolIds = ["parent_t"]
        let nameMap: [String: String] = ["parent_t": "Bash"]

        let line = #"{"type":"progress","parentToolUseID":"parent_t","data":{"type":"bash_progress"}}"#

        let events = parser.parseLineWithToolNames(line, session: &session, parentNames: nameMap)
        XCTAssertTrue(events.isEmpty)
    }

    func testProgressSubagentToolCompletion() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolIds = ["parent_t"]
        session.subagentTools["parent_t"] = ["sub_t"]
        let nameMap: [String: String] = ["parent_t": "Task"]

        let line = #"{"type":"progress","parentToolUseID":"parent_t","data":{"type":"agent_progress","message":{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"sub_t"}]}}}}"#

        let events = parser.parseLineWithToolNames(line, session: &session, parentNames: nameMap)
        XCTAssertEqual(events, [.subagentToolCompleted(parentId: "parent_t", toolId: "sub_t")])
        XCTAssertEqual(session.subagentTools["parent_t"], [])
    }

    func testActiveToolNamesPopulatedAndCleared() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")

        let useLine = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}"#
        _ = parser.parseLine(useLine, session: &session)
        XCTAssertEqual(session.activeToolNames["t1"], "Bash")

        let resultLine = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#
        _ = parser.parseLine(resultLine, session: &session)
        XCTAssertNil(session.activeToolNames["t1"])
    }

    func testTurnDurationClearsActiveToolNames() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        session.activeToolNames["t1"] = "Bash"

        let line = #"{"type":"system","subtype":"turn_duration"}"#
        _ = parser.parseLine(line, session: &session)
        XCTAssertTrue(session.activeToolNames.isEmpty)
    }
}
