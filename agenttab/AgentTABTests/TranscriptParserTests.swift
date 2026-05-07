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
}
