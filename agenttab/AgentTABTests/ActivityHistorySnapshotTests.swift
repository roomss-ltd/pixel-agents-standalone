import XCTest
import Combine
import SwiftUI
import AppKit
@testable import AgentTAB

/// Renders `ActivityHistoryView` offscreen via `ImageRenderer` into PNGs.
/// Doubles as (a) a smoke test that the dashboard composes and renders
/// without trapping in any mode, and (b) an artifact generator for visual
/// review of the tokens/active/agent modes and the two-row hover chip.
@MainActor
final class ActivityHistorySnapshotTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tt-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeLine(
        project: String, session: String,
        daysAgo: Int, secondsIntoDay: Int,
        input: Int = 0
    ) throws {
        let projectDir = tempRoot.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")
        let cal = Calendar.current
        let dayStart = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        let ts = dayStart.addingTimeInterval(TimeInterval(secondsIntoDay))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line: [String: Any] = [
            "type": "assistant",
            "timestamp": iso.string(from: ts),
            "message": ["usage": ["input_tokens": input]],
        ]
        let data = try JSONSerialization.data(withJSONObject: line)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: file.path) {
            handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
        }
        handle.write(data); handle.write("\n".data(using: .utf8)!); try handle.close()
    }

    private func waitForScan(_ tracker: TokenTracker) async {
        let exp = XCTestExpectation(description: "history published")
        let c = tracker.$daysWindow.dropFirst().sink { _ in exp.fulfill() }
        await fulfillment(of: [exp], timeout: 2.0)
        c.cancel()
    }

    private func renderPNG(_ view: some View, size: CGSize, to name: String) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(12)
                .background(Color.black)
        )
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image for \(name)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        try png.write(to: url)
        XCTAssertGreaterThan(png.count, 2_000, "\(name) PNG suspiciously small (\(png.count) bytes)")
        print("SNAPSHOT \(name): \(png.count) bytes → \(url.path)")
    }

    func testRendersAllModes() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // A varied week: several days, several sessions today so the
        // agent-hours total visibly exceeds the wall-clock span.
        try writeLine(project: "-Users-x-Desktop-pixel-agents", session: "a1", daysAgo: 6, secondsIntoDay: 30_000, input: 200_000)
        try writeLine(project: "-Users-x-Desktop-pixel-agents", session: "a1", daysAgo: 6, secondsIntoDay: 31_200, input: 150_000)
        try writeLine(project: "-Users-x-Desktop-infra",        session: "b1", daysAgo: 5, secondsIntoDay: 40_000, input: 900_000)
        try writeLine(project: "-Users-x-Desktop-pixel-agents", session: "a2", daysAgo: 3, secondsIntoDay: 20_000, input: 600_000)
        try writeLine(project: "-Users-x-Desktop-pixel-agents", session: "a2", daysAgo: 3, secondsIntoDay: 23_600, input: 450_000)
        try writeLine(project: "-Users-x-Desktop-infra",        session: "b2", daysAgo: 1, secondsIntoDay: 50_000, input: 300_000)

        // Today: three overlapping sessions across the morning so the
        // hover chip shows a meaningful active vs agent-time split.
        for (i, base) in [25_200, 25_800, 27_000].enumerated() {
            for t in stride(from: base, through: base + 1_800, by: 120) {
                try writeLine(project: "-Users-x-Desktop-pixel-agents", session: "today\(i)", daysAgo: 0, secondsIntoDay: t, input: 50_000)
            }
        }

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let size = CGSize(width: 384, height: 470)
        try renderPNG(
            ActivityHistoryView(tracker: tracker, onBack: {}, initialMode: .tokens),
            size: size, to: "agenttab-snap-1-tokens.png"
        )
        try renderPNG(
            ActivityHistoryView(tracker: tracker, onBack: {}, initialMode: .active, initialHoveredDay: today),
            size: size, to: "agenttab-snap-2-active-hover.png"
        )
        try renderPNG(
            ActivityHistoryView(tracker: tracker, onBack: {}, initialMode: .agent, initialHoveredDay: today),
            size: size, to: "agenttab-snap-3-agent-hover.png"
        )
    }
}
