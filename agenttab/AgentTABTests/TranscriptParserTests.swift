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
        // A turn that ended without an explicit permission request is `.done`,
        // not `.waiting` — `.waiting` is reserved for the PermissionRequest
        // hook. Calling every finished turn "waiting" is precisely the
        // mis-flagging this suite exists to prevent.
        XCTAssertEqual(session.activity, .done)
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }

    // MARK: - Liveness / stuck-state regressions

    func testToolResultReleasesSessionBackToThinking() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")

        let use = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a.swift"}}]}}"#
        _ = parser.parseLine(use, session: &session)
        XCTAssertEqual(session.activity, .tool("Read"))

        let result = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#
        _ = parser.parseLine(result, session: &session)

        // Without this, `.tool` is a one-way door: most transcripts never emit
        // a `turn_duration` record, so a session that finished normally would
        // sit at `.tool(Read)` — reading as "processing" — forever.
        XCTAssertEqual(session.activity, .thinking)
        XCTAssertNil(session.currentTool)
    }

    func testToolResultKeepsToolStateWhileOtherToolsStillRunning() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")

        let useA = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a.swift"}}]}}"#
        let useB = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"ls"}}]}}"#
        _ = parser.parseLine(useA, session: &session)
        _ = parser.parseLine(useB, session: &session)

        let resultA = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#
        _ = parser.parseLine(resultA, session: &session)

        // t2 is still in flight — the agent is genuinely still running a tool.
        XCTAssertEqual(session.activity, .tool("Bash"))
        XCTAssertEqual(session.activeToolIds, ["t2"])
    }

    func testRecordTimestampAnchorsUpdateAndEvidence() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")

        let line = #"{"type":"assistant","timestamp":"2026-07-14T12:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a.swift"}}]}}"#
        _ = parser.parseLine(line, session: &session)

        let expected = ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z")!
        // The watcher replays a transcript from byte 0 the first time it sees
        // it, so records routinely arrive minutes after they were written.
        // Stamping `Date()` would make every replayed session look live.
        XCTAssertEqual(session.lastUpdate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.lastEvidence?.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testEvidenceNeverMovesBackwards() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")

        let newer = #"{"type":"assistant","timestamp":"2026-07-14T12:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a.swift"}}]}}"#
        let older = #"{"type":"assistant","timestamp":"2026-07-14T11:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t0","name":"Read","input":{"file_path":"/b.swift"}}]}}"#
        _ = parser.parseLine(newer, session: &session)
        _ = parser.parseLine(older, session: &session)

        let expected = ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z")!
        XCTAssertEqual(session.lastEvidence?.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 1)
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
