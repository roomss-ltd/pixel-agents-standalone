import XCTest
import SwiftUI
import AppKit
@testable import AgentTAB

/// Renders the ported idle cast to PNGs so the 1:1 port from the design
/// handoff can be eyeballed: a frame-0 grid of all 13 characters plus a
/// 4-frame filmstrip for a couple of them to confirm animation frames.
/// Also a render-regression smoke test that every sprite produces images.
@MainActor
final class IdleSpritesSnapshotTests: XCTestCase {

    private func frame(_ sprite: IdleSprite, _ f: Int, size: CGFloat) -> some View {
        let imgs = sprite.frameImages()
        return Group {
            if imgs.indices.contains(f) {
                Image(decorative: imgs[f], scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Color.red.frame(width: size, height: size)
            }
        }
    }

    private func renderPNG(_ view: some View, size: CGSize, to name: String) throws {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color(red: 0.04, green: 0.05, blue: 0.06))
        )
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "no image for \(name)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/\(name)"))
        XCTAssertGreaterThan(png.count, 2_000)
        print("SNAPSHOT \(name): \(png.count) bytes → /tmp/\(name)")
    }

    func testEverySpriteProducesFourFrameImages() {
        XCTAssertEqual(IdleSprite.cast.count, 13)
        for sprite in IdleSprite.cast {
            XCTAssertEqual(sprite.frameImages().count, 4, "\(sprite.name) should render 4 frames")
            XCTAssertFalse(sprite.palette.isEmpty, "\(sprite.name) palette")
        }
    }

    func testRendersIdleCast() throws {
        let cell: CGFloat = 52
        let grid = VStack(alignment: .leading, spacing: 14) {
            Text("idle cast · frame 0").font(.system(size: 11)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 10), count: 5), spacing: 12) {
                ForEach(IdleSprite.cast.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        self.frame(IdleSprite.cast[i], 0, size: cell)
                        Text(IdleSprite.cast[i].name)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                }
            }
            Text("filmstrips · all 4 frames").font(.system(size: 11)).foregroundStyle(.white)
            // slime (0), bee (11), smoke-break (12) exercise squish, wing-flap, steam.
            ForEach([0, 11, 12], id: \.self) { si in
                HStack(spacing: 8) {
                    ForEach(0 ..< 4, id: \.self) { f in
                        self.frame(IdleSprite.cast[si], f, size: cell)
                    }
                    Text(IdleSprite.cast[si].name)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(20)
        try renderPNG(grid, size: CGSize(width: 380, height: 560), to: "idle-cast.png")
    }
}
