import XCTest
@testable import AgentTAB

/// End-to-end test: hook script (simulated by a `nc -U` Process) writes
/// JSON to the Unix socket; HookSocketListener decodes and fires onPayload.
///
/// This test MUST exist because if NWListener.unix breaks on a particular
/// macOS version, the failure is otherwise silent — the engine just
/// stops receiving hook events with no error surface.
final class HookSocketIntegrationTests: XCTestCase {
    func testListenerReceivesPayloadFromUnixSocketWrite() async throws {
        let socketPath = "/tmp/agenttab-test-\(UUID().uuidString).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        let listener = HookSocketListener(socketPath: socketPath)
        let expectation = XCTestExpectation(description: "onPayload fires")
        var received: HookPayload?

        listener.onPayload = { payload in
            received = payload
            expectation.fulfill()
        }
        try listener.start()
        defer { listener.stop() }

        // Give NWListener a moment to bind the socket.
        try await Task.sleep(for: .milliseconds(200))

        // Verify the socket file exists.
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath),
                      "socket file should exist after listener.start()")

        // Spawn `nc -U` to write a payload.
        let payload = #"{"pane_id":7,"session_id":"sess_xyz","hook_event":"PreToolUse","tool_name":"Bash","term_program":"ghostty"}"#
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", "printf '%s' '\(payload)' | nc -U '\(socketPath)' -w 1"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "nc -U should exit cleanly")

        // Wait for onPayload, max 2 seconds.
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertNotNil(received)
        XCTAssertEqual(received?.paneId, 7)
        XCTAssertEqual(received?.sessionId, "sess_xyz")
        XCTAssertEqual(received?.hookEvent, "PreToolUse")
        XCTAssertEqual(received?.toolName, "Bash")
        XCTAssertEqual(received?.termProgram, "ghostty")
    }

    func testListenerHandlesMultipleSequentialWrites() async throws {
        let socketPath = "/tmp/agenttab-test-\(UUID().uuidString).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        let listener = HookSocketListener(socketPath: socketPath)
        let expectation = XCTestExpectation(description: "two payloads fire")
        expectation.expectedFulfillmentCount = 2

        var received: [HookPayload] = []
        listener.onPayload = { payload in
            received.append(payload)
            expectation.fulfill()
        }
        try listener.start()
        defer { listener.stop() }

        try await Task.sleep(for: .milliseconds(200))

        for sessionId in ["s1", "s2"] {
            let payload = "{\"pane_id\":null,\"session_id\":\"\(sessionId)\",\"hook_event\":\"Stop\"}"
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = ["-c", "printf '%s' '\(payload)' | nc -U '\(socketPath)' -w 1"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(received.count, 2)
        let ids = received.map(\.sessionId).sorted()
        XCTAssertEqual(ids, ["s1", "s2"])
    }
}
