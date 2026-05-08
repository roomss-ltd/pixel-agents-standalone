import XCTest
@testable import AgentTAB

final class JSONLPipelineIntegrationTests: XCTestCase {
    func testEngineDiscoversSessionFromTempProjectDir() async throws {
        let tempProjectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-test-\(UUID().uuidString)")
        let projectDir = tempProjectsDir.appendingPathComponent("-Users-test-Desktop-myapp")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Pre-create a JSONL with one tool_use record
        let jsonlURL = projectDir.appendingPathComponent("session-abc.jsonl")
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x.swift"}}]}}\#n"#
        try line.write(to: jsonlURL, atomically: true, encoding: .utf8)

        let engine = await ActivityEngine(projectsDir: tempProjectsDir)
        await engine.start()

        // Wait for async discovery
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            XCTAssertEqual(engine.sessions.count, 1)
            XCTAssertEqual(engine.sessions.first?.projectName, "myapp")
            XCTAssertEqual(engine.sessions.first?.currentTool, "Reading x.swift")
        }

        try? FileManager.default.removeItem(at: tempProjectsDir)
    }
}
