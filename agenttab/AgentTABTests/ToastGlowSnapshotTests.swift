import XCTest
import SwiftUI
import AppKit
@testable import AgentTAB

/// Demonstrates the toast glow fix: when the host is sized exactly to the
/// card, the accent glow is hard-clipped into a square halo; padding the
/// host (as ToastPanel now does) lets it bloom round.
@MainActor
final class ToastGlowSnapshotTests: XCTestCase {

    private func renderPNG(_ view: some View, size: CGSize, to name: String) throws {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
                .background(Color(red: 0.04, green: 0.05, blue: 0.06))
        )
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/\(name)"))
        print("SNAPSHOT \(name): \(png.count) bytes")
    }

    func testToastGlowClippedVsRounded() throws {
        let toast = Toast(variant: .success, taskId: "16", projectName: "agenttab", message: "Finished in 2m 14s")
        let card = ToastView(toast: toast)

        let comparison = VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("clipped to card bounds (bug)").font(.system(size: 10)).foregroundStyle(.white)
                card
                    .frame(width: 360, height: 62)
                    .clipped()          // mimics the old card-sized window
            }
            VStack(spacing: 6) {
                Text("padded host (fix)").font(.system(size: 10)).foregroundStyle(.white)
                card.padding(48)        // mimics the new glow-margin panel
            }
        }
        .padding(24)

        try renderPNG(comparison, size: CGSize(width: 480, height: 320), to: "toast-glow.png")
    }
}
