import AppKit
import XCTest
@testable import AgentTAB

@MainActor
final class AgentTABTests: XCTestCase {
    func testBillionTokenTotalsKeepEnoughPrecisionToShowLiveGrowth() {
        XCTAssertEqual(TokenTracker.format(1_157_471_860), "1.16B")
    }

    func testDismissingToastReleasesItsAnimatedHostingView() {
        let panel = ToastPanel()
        panel.contentView = NSView()
        panel.dismiss()
        XCTAssertNil(panel.contentView)
    }

    func testDoubleDigitBadgeCountUsesSmallerSingleLineType() {
        XCTAssertEqual(CountBadgeTypography.size(base: 13, count: 9), 13)
        XCTAssertLessThan(CountBadgeTypography.size(base: 13, count: 10), 11)
        XCTAssertLessThan(CountBadgeTypography.size(base: 13, count: 100), 9)
    }

    func testUpdaterDoesNotStartInsideXCTestHost() {
        XCTAssertFalse(UpdaterCoordinator.shouldStartUpdater(environment: [
            "XCTestConfigurationFilePath": "/tmp/AgentTAB.xctestconfiguration"
        ]))
        XCTAssertTrue(UpdaterCoordinator.shouldStartUpdater(environment: [:]))
    }

    func testPixelCellStylePreservesExistingOpacityAndGlowMath() {
        let lit = PixelMath.cellStyle(
            isActive: true,
            rawBrightness: 0.5,
            brightness: 0.8,
            baseOpacity: 0.12,
            cellSize: 6,
            glow: 0.75
        )
        XCTAssertEqual(lit.opacity, 0.472, accuracy: 0.000_001)
        XCTAssertEqual(lit.shadowRadius, 1.71, accuracy: 0.000_001)
        XCTAssertTrue(lit.showsGlow)

        let dim = PixelMath.cellStyle(
            isActive: false,
            rawBrightness: 1,
            brightness: 1,
            baseOpacity: 0.12,
            cellSize: 6,
            glow: 1
        )
        XCTAssertEqual(dim.opacity, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(dim.shadowRadius, 5.7, accuracy: 0.000_001)
        XCTAssertFalse(dim.showsGlow)
    }

    func testPixelLayerRendererKeepsGridGeometryAndPaletteTiming() throws {
        let view = PixelLoopLayerView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        view.configure(
            variant: .chaosRotate,
            size: 18,
            coreColor: NSColor(PixelLoopPalette.blue.core),
            glowColor: NSColor(PixelLoopPalette.blue.glow),
            running: false,
            brightness: 1,
            glow: 1,
            speed: 1,
            baseOpacity: 0.12,
            paletteCrossfadeDuration: 1.6
        )
        view.layoutSubtreeIfNeeded()

        let layers = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(layers.count, 9)
        XCTAssertEqual(view.intrinsicContentSize, NSSize(width: 18, height: 18))
        XCTAssertEqual(layers[0].frame.width, 5.04, accuracy: 0.000_001)
        XCTAssertEqual(layers[1].frame.minX, 6.48, accuracy: 0.000_001)
        XCTAssertEqual(layers[0].cornerRadius, 2)
        XCTAssertEqual(layers[0].cornerCurve, .continuous)

        view.configure(
            variant: .chaosRotate,
            size: 18,
            coreColor: NSColor(PixelLoopPalette.pink.core),
            glowColor: NSColor(PixelLoopPalette.pink.glow),
            running: true,
            brightness: 1,
            glow: 1,
            speed: 1,
            baseOpacity: 0.12,
            paletteCrossfadeDuration: 1.6
        )
        let transition = try XCTUnwrap(
            layers[0].animation(forKey: "agenttab.palette.fill") as? CABasicAnimation
        )
        XCTAssertEqual(transition.duration, 1.6, accuracy: 0.000_001)
    }

    func testConnectedClientCountForDetachedSession() {
        XCTAssertEqual(
            ActivityEngine.connectedClientCount(
                from: "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n"
            ),
            0
        )
    }

    func testConnectedClientCountForAttachedSession() {
        XCTAssertEqual(
            ActivityEngine.connectedClientCount(
                from: "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n1 terminal_0 codex\n"
            ),
            1
        )
    }

    func testConnectedClientCountRejectsUnexpectedOutput() {
        XCTAssertNil(ActivityEngine.connectedClientCount(from: "zellij failed\n"))
    }

    func testZellijClientRejectsProtectedDesktopLocation() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertFalse(ZellijStatusReader.isSafeZellijLocation(
            URL(fileURLWithPath: "/Users/tester/Desktop/project/zellij"),
            homeDirectory: home
        ))
        XCTAssertTrue(ZellijStatusReader.isSafeZellijLocation(
            URL(fileURLWithPath: "/Users/tester/Library/Application Support/AgentTAB/zellij"),
            homeDirectory: home
        ))
    }

    func testAgentTABStripsTheZellijOnlyWorkingMarker() {
        XCTAssertEqual(ZellijStatusReader.displayTabName("Agenttab ●"), "Agenttab")
        XCTAssertEqual(ZellijStatusReader.displayTabName("Release ● notes"), "Release ● notes")
    }

    func testZellijStatusPreservesAgentKind() throws {
        let json = #"{"sessions":[{"pane_id":4,"run_id":"codex-id:4:1:1","tab_num":2,"tab_name":"Work","icon":"⚡","detail":"Bash","activity":"Tool","cwd":"/tmp/work","agent_kind":"codex","agent_title":"Fix memory"}],"counts":{"active":1,"waiting":0,"done":0},"updated_at":1}"#
        let status = try JSONDecoder().decode(ZellijStatusFile.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(status)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])

        XCTAssertEqual(sessions.first?["agent_kind"] as? String, "codex")
        XCTAssertEqual(sessions.first?["agent_title"] as? String, "Fix memory")
    }

    func testDiscoversMissingDevinPaneFromReadOnlyZellijMetadata() throws {
        let json = #"""
        [
          {"id":1,"is_plugin":false,"exited":false,"title":"codex-yolo","tab_position":0,"tab_name":"Work","pane_command":"codex","pane_cwd":"/tmp/work"},
          {"id":7,"is_plugin":false,"exited":false,"title":"devin: what can you do?","tab_position":4,"tab_name":"Pandora","pane_command":"devin","pane_cwd":"/tmp/devin"}
        ]
        """#

        let sessions = ZellijStatusReader.devinSessions(
            fromPaneList: Data(json.utf8),
            excluding: [1],
            now: 123
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.paneId, 7)
        XCTAssertEqual(sessions.first?.tabNum, 5)
        XCTAssertEqual(sessions.first?.tabName, "Pandora")
        XCTAssertEqual(sessions.first?.agentKind, "devin")
        XCTAssertEqual(sessions.first?.agentTitle, "what can you do?")
        XCTAssertEqual(sessions.first?.cwd, "/tmp/devin")
    }
}
