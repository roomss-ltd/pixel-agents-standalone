import XCTest
@testable import AgentTAB

final class PermissionTimerTests: XCTestCase {
    func testFiresAfter5SecondsWithActiveNonExemptTool() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: true) { fired = true }

        try await Task.sleep(for: .seconds(6))
        XCTAssertTrue(fired)
    }

    func testDoesNotFireForExemptToolsOnly() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: false) { fired = true }

        try await Task.sleep(for: .seconds(6))
        XCTAssertFalse(fired)
    }

    func testCanCancel() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: true) { fired = true }
        timer.cancel(for: "session1")

        try await Task.sleep(for: .seconds(6))
        XCTAssertFalse(fired)
    }
}
