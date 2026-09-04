import XCTest
@testable import AgentTAB

final class JSONLPipelineIntegrationTests: XCTestCase {
    /// An empty status dir, so an engine under test never adopts the Zellij
    /// panes of whoever is running the suite. Without this the engine reads
    /// the real /tmp/claude-tab-status and every session-count assertion
    /// depends on how many agents the developer happens to have open.
    private func makeIsolatedStatusDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEngineDiscoversSessionFromTempProjectDir() async throws {
        let tempProjectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-test-\(UUID().uuidString)")
        let projectDir = tempProjectsDir.appendingPathComponent("-Users-test-Desktop-myapp")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()

        // Pre-create a JSONL with one tool_use record
        let jsonlURL = projectDir.appendingPathComponent("session-abc.jsonl")
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x.swift"}}]}}\#n"#
        try line.write(to: jsonlURL, atomically: true, encoding: .utf8)

        let engine = await ActivityEngine(projectsDir: tempProjectsDir, zellijStatusDir: statusDir)
        await engine.start()

        // Wait for async discovery
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            XCTAssertEqual(engine.sessions.count, 1)
            XCTAssertEqual(engine.sessions.first?.projectName, "myapp")
            XCTAssertEqual(engine.sessions.first?.currentTool, "Reading x.swift")
        }

        try? FileManager.default.removeItem(at: tempProjectsDir)
        try? FileManager.default.removeItem(at: statusDir)
    }

    func testEmptyZellijSnapshotDoesNotExposeUnmatchedTranscriptHistory() async throws {
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-empty-zellij-\(UUID().uuidString)")
        let projectDir = projectsDir.appendingPathComponent("-Users-test-Desktop-old-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: statusDir)
        }

        try "{}\n".write(
            to: projectDir.appendingPathComponent("historical-session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let now = Int(Date().timeIntervalSince1970)
        try "{\"sessions\":[],\"counts\":{\"active\":0,\"waiting\":0,\"done\":0},\"updated_at\":\(now)}"
            .write(
                to: statusDir.appendingPathComponent("empty-session.json"),
                atomically: true,
                encoding: .utf8
            )

        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            XCTAssertTrue(engine.zellijDetected)
            XCTAssertEqual(engine.sessions.count, 1, "the transcript remains available internally")
            XCTAssertTrue(
                engine.displaySessions.isEmpty,
                "an empty live Zellij snapshot must render an empty agent list"
            )
        }
    }

    // MARK: - Zellij ghost panes

    /// The bug as it appears in the wild: a Zellij pane whose agent died weeks
    /// ago, still published as `Thinking` every 5 seconds because the plugin
    /// only ever decays `Done → Idle` and only evicts a session when its *pane*
    /// disappears. The pane is still open, so the ghost is immortal.
    func testGhostZellijPaneIsNotReportedAsProcessing() async throws {
        let sessionId = "47b6e6fa-918a-49ed-9fea-374fe312c828"
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-ghost-\(UUID().uuidString)")
        let projectDir = projectsDir.appendingPathComponent("-Users-test-Desktop-cyndex")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: statusDir)
        }

        // The agent's transcript: last written a month ago. This is the only
        // signal that can expose the ghost, and it survives an app restart.
        let diedAt = Date().addingTimeInterval(-30 * 24 * 3600)
        let jsonlURL = projectDir.appendingPathComponent("\(sessionId).jsonl")
        try "{}\n".write(to: jsonlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: diedAt], ofItemAtPath: jsonlURL.path
        )

        // The plugin's status file, freshly written *right now*, still insisting
        // the pane is Thinking — exactly what a live plugin publishes for a
        // pane whose agent was killed without sending Stop/SessionEnd.
        let now = Int(Date().timeIntervalSince1970)
        let status = """
        {"sessions":[{"pane_id":0,"run_id":"\(sessionId):0:1781533412:79","tab_num":1,\
        "tab_name":"Cyndex","icon":"●","detail":"Write","activity":"Thinking","cwd":null}],\
        "counts":{"active":1,"waiting":0,"done":0},"updated_at":\(now)}
        """
        try status.write(
            to: statusDir.appendingPathComponent("charming-newt.json"),
            atomically: true, encoding: .utf8
        )

        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            // The composite run_id must resolve to the bare Claude session id,
            // or the row can never be matched to the transcript that exposes it.
            let ghost = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertNotNil(ghost, "zellij pane should key on the run_id's session prefix")

            engine.sweepStaleSessions()

            let after = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(after?.activity, .idle, "a pane whose agent died a month ago is not processing")
        }

        // The plugin keeps publishing "Thinking" for this pane every 5s. The
        // demotion has to survive that: if the reader adopts the republished
        // claim, the row flips idle → tool → idle forever and the notch
        // flickers. Wait out more than one poll cycle and re-check.
        try await Task.sleep(for: .seconds(7))

        await MainActor.run {
            let settled = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(settled?.activity, .idle, "a republished stale claim must not resurrect the ghost")
        }
    }

    /// The harder ghost: old enough that Claude has already rotated its
    /// transcript away, so there is no mtime to convict it with. All we can do
    /// is watch: the plugin republishes the same activity every 5s and a truly
    /// live agent would write *something* within the stale window, so a pane
    /// that never does is dead.
    func testGhostWithNoTranscriptIsSweptOnTheFirstSeenClock() async throws {
        let sessionId = "1e3188b8-c7b8-4501-a3e0-37f85b576f46"
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-notx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: statusDir)
        }

        // Note: no transcript is written for this session id anywhere.
        let now = Int(Date().timeIntervalSince1970)
        let status = """
        {"sessions":[{"pane_id":1,"run_id":"\(sessionId):1:1780940990:41","tab_num":2,\
        "tab_name":"QB Monitor","icon":"⚡","detail":"Read","activity":"Tool","cwd":null}],\
        "counts":{"active":1,"waiting":0,"done":0},"updated_at":\(now)}
        """
        try status.write(
            to: statusDir.appendingPathComponent("charming-newt.json"),
            atomically: true, encoding: .utf8
        )

        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            // run_id says this turn began 36 days ago (1780940990), there is no
            // transcript, and no hook has ever reached us. Nothing runs for a
            // day — convict it on sight rather than granting it a fresh grace
            // period every time the app restarts.
            let ghost = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(ghost?.activity, .idle, "a turn 'running' since last month is a corpse")
        }
    }

    /// The same shape, but the run started minutes ago: an agent we've simply
    /// only just met. It must be taken at its word until it actually goes quiet.
    func testRecentlyStartedPaneWithNoTranscriptIsTrustedUntilItGoesQuiet() async throws {
        let sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: statusDir)
        }

        // No transcript — this is what a live Codex agent looks like to us.
        let now = Int(Date().timeIntervalSince1970)
        let runStart = now - 120
        let status = """
        {"sessions":[{"pane_id":4,"run_id":"\(sessionId):4:\(runStart):9","tab_num":1,\
        "tab_name":"Codex","icon":"⚡","detail":"Read","activity":"Tool","cwd":null}],\
        "counts":{"active":1,"waiting":0,"done":0},"updated_at":\(now)}
        """
        try status.write(
            to: statusDir.appendingPathComponent("s.json"),
            atomically: true, encoding: .utf8
        )

        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            let fresh = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(fresh?.activity, .tool("Read"), "a recently-started agent is not a ghost")

            engine.sweepStaleSessions()
            let stillWorking = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(stillWorking?.activity, .tool("Read"), "the sweep must not touch it yet")

            // Now it has gone quiet past the window with nothing to show for it.
            engine.sweepStaleSessions(now: Date().addingTimeInterval(ActivityEngine.transientStaleTimeout + 60))
            let swept = engine.sessions.first { $0.claudeSessionId == sessionId }
            XCTAssertEqual(swept?.activity, .idle)
        }
    }

    /// Two Zellij sessions each have a tab 2. They are different tabs, and each
    /// row must read plainly as "2" — not "2.1" / "2.2", which is the label for
    /// two panes *splitting one tab*. Getting this wrong also makes labels
    /// flicker, because the peer set changes every time a row appears or leaves.
    func testTabLabelsDoNotCollideAcrossZellijSessions() async throws {
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-label-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let statusDir = try makeIsolatedStatusDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: statusDir)
        }

        let now = Int(Date().timeIntervalSince1970)
        let recent = now - 60
        func file(pane: Int, session: String) -> String {
            """
            {"sessions":[{"pane_id":\(pane),"run_id":"sess-\(pane):\(pane):\(recent):1","tab_num":2,\
            "tab_name":"\(session)-tab2","icon":"⚡","detail":"Read","activity":"Tool","cwd":null}],\
            "counts":{"active":1,"waiting":0,"done":0},"updated_at":\(now)}
            """
        }
        try file(pane: 1, session: "alpha")
            .write(to: statusDir.appendingPathComponent("alpha.json"), atomically: true, encoding: .utf8)
        try file(pane: 2, session: "beta")
            .write(to: statusDir.appendingPathComponent("beta.json"), atomically: true, encoding: .utf8)

        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))

        await MainActor.run {
            let labels = engine.displaySessions.map { engine.displayLabel(for: $0) }
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(Set(labels), ["2"], "tab numbers are per-session, not global")
        }
    }

    func testRunStartIsRecoveredFromRunId() {
        XCTAssertEqual(
            ActivityEngine.runStart(fromRunId: "1e3188b8-c7b8-4501-a3e0-37f85b576f46:1:1780940990:41"),
            Date(timeIntervalSince1970: 1780940990)
        )
        XCTAssertNil(ActivityEngine.runStart(fromRunId: "no-colons-here"))
    }

    // MARK: - Ghost sessions

    /// Build an engine over a temp projects dir holding one transcript whose
    /// last record is an unfinished tool call — the shape every transcript has
    /// when an agent is killed mid-tool, and the shape most have when they
    /// simply end (only ~17% of real transcripts contain a `turn_duration`).
    /// `age` back-dates both the record and the file mtime.
    private func makeEngineWithStalledToolSession(
        sessionId: String,
        age: TimeInterval
    ) async throws -> (ActivityEngine, URL) {
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-ghost-\(UUID().uuidString)")
        let projectDir = projectsDir.appendingPathComponent("-Users-test-Desktop-myapp")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let writtenAt = Date().addingTimeInterval(-age)
        let stamp = ISO8601DateFormatter().string(from: writtenAt)
        let jsonlURL = projectDir.appendingPathComponent("\(sessionId).jsonl")
        let line = """
        {"type":"assistant","timestamp":"\(stamp)","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}

        """
        try line.write(to: jsonlURL, atomically: true, encoding: .utf8)
        // The transcript's mtime is the engine's proof of life, so it has to
        // be back-dated too — a file we just wrote is, correctly, evidence of
        // a live agent.
        try FileManager.default.setAttributes(
            [.modificationDate: writtenAt], ofItemAtPath: jsonlURL.path
        )

        let statusDir = try makeIsolatedStatusDir()
        let engine = await ActivityEngine(projectsDir: projectsDir, zellijStatusDir: statusDir)
        await engine.start()
        try await Task.sleep(for: .seconds(2))
        return (engine, projectsDir)
    }

    func testStalledToolSessionIsSweptToIdle() async throws {
        let id = "ghost-\(UUID().uuidString)"
        // 20 minutes of silence — past the 15-minute stale threshold.
        let (engine, dir) = try await makeEngineWithStalledToolSession(sessionId: id, age: 20 * 60)
        defer { try? FileManager.default.removeItem(at: dir) }

        await MainActor.run {
            let before = engine.sessions.first { $0.claudeSessionId == id }
            XCTAssertEqual(before?.activity, .tool("Bash"), "replay should leave the session mid-tool")

            engine.sweepStaleSessions()

            let after = engine.sessions.first { $0.claudeSessionId == id }
            // The agent was killed: no Stop, no SessionEnd, no further writes.
            // Nothing but the sweep can ever move it off `.tool`.
            XCTAssertEqual(after?.activity, .idle, "a silent tool session must not stay 'processing'")
            XCTAssertNil(after?.currentTool)
            XCTAssertTrue(after?.activeToolIds.isEmpty ?? false)
        }
    }

    func testSweptSessionIsAnchoredToItsLastEvidenceNotToNow() async throws {
        let id = "ghost-\(UUID().uuidString)"
        let age: TimeInterval = 20 * 60
        let (engine, dir) = try await makeEngineWithStalledToolSession(sessionId: id, age: age)
        defer { try? FileManager.default.removeItem(at: dir) }

        await MainActor.run {
            engine.sweepStaleSessions()
            let swept = engine.sessions.first { $0.claudeSessionId == id }
            let silence = Date().timeIntervalSince(swept?.lastUpdate ?? Date())
            // It buckets into RECENTLY / OLDER FINISHED by when the agent
            // actually stopped, not by when we happened to notice.
            XCTAssertEqual(silence, age, accuracy: 60)
        }
    }

    func testLongRunningToolSurvivesTheSweep() async throws {
        let id = "live-\(UUID().uuidString)"
        // 10 minutes into a slow Bash call: silent, but legitimately working.
        let (engine, dir) = try await makeEngineWithStalledToolSession(sessionId: id, age: 10 * 60)
        defer { try? FileManager.default.removeItem(at: dir) }

        await MainActor.run {
            engine.sweepStaleSessions()
            let after = engine.sessions.first { $0.claudeSessionId == id }
            XCTAssertEqual(after?.activity, .tool("Bash"), "a tool under the threshold is still running")
        }
    }

    func testRunIdYieldsTheClaudeSessionIdItsPrefix() {
        // The plugin mints run ids as "{session_id}:{pane_id}:{unix}:{seq}".
        // Keying on the whole composite gives each agent two Session rows and
        // routes its hooks to the one the UI hides.
        XCTAssertEqual(
            ActivityEngine.claudeSessionId(fromRunId: "47b6e6fa-918a-49ed-9fea-374fe312c828:0:1781533412:79"),
            "47b6e6fa-918a-49ed-9fea-374fe312c828"
        )
        // The plugin writes an empty prefix when it never saw a session_id.
        XCTAssertNil(ActivityEngine.claudeSessionId(fromRunId: ":72:1783897613:2638"))
        XCTAssertNil(ActivityEngine.claudeSessionId(fromRunId: ""))
    }
}
