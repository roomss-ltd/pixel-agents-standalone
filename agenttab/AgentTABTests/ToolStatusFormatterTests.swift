import XCTest
@testable import AgentTAB

final class ToolStatusFormatterTests: XCTestCase {
    func testFormatsRead() {
        let result = ToolStatusFormatter.format(toolName: "Read",
                                                input: ["file_path": "/a/b/c.swift"])
        XCTAssertEqual(result, "Reading c.swift")
    }

    func testFormatsEdit() {
        let result = ToolStatusFormatter.format(toolName: "Edit",
                                                input: ["file_path": "/a/b/main.py"])
        XCTAssertEqual(result, "Editing main.py")
    }

    func testFormatsBashShortCommand() {
        let result = ToolStatusFormatter.format(toolName: "Bash",
                                                input: ["command": "ls -la"])
        XCTAssertEqual(result, "Running: ls -la")
    }

    func testFormatsBashLongCommandTruncates() {
        let cmd = String(repeating: "x", count: 100)
        let result = ToolStatusFormatter.format(toolName: "Bash",
                                                input: ["command": cmd])
        XCTAssertEqual(result.count, "Running: ".count + 50 + 1)  // 50 chars + ellipsis
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
    }

    func testFormatsTaskWithDescription() {
        let result = ToolStatusFormatter.format(toolName: "Task",
                                                input: ["description": "Find auth bugs"])
        XCTAssertEqual(result, "Subtask: Find auth bugs")
    }

    func testFormatsUnknownTool() {
        let result = ToolStatusFormatter.format(toolName: "MysteryTool", input: [:])
        XCTAssertEqual(result, "Using MysteryTool")
    }

    func testFormatsAskUserQuestion() {
        let result = ToolStatusFormatter.format(toolName: "AskUserQuestion", input: [:])
        XCTAssertEqual(result, "Waiting for your answer")
    }
}
