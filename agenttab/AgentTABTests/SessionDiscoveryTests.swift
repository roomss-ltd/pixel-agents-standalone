import XCTest
@testable import AgentTAB

final class SessionDiscoveryTests: XCTestCase {
    func testExtractsRepoNameFromSimpleProject() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo")
        XCTAssertEqual(result, "my-repo")
    }

    func testExtractsRepoSlashBranchFromWorktree() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo--worktrees-feat-x")
        XCTAssertEqual(result, "my-repo/feat-x")
    }

    func testFallsBackToLastSegmentIfDesktopMissing() {
        let result = SessionDiscovery.hashToProjectName("foo-bar-baz")
        XCTAssertEqual(result, "baz")
    }
}
