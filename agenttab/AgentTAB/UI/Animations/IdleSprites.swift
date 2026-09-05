// IdleSprites.swift — pixel-art idle cast ported 1:1 from the Claude
// Design handoff "Idle Animations.html".
//
// Each character is a 24×24 sprite with a small per-sprite hex palette
// and 4 frames; '.' is transparent and any hex digit (0–f) indexes into
// the palette. Frames advance at the sprite's own `fps` (frame index =
// floor(elapsed · fps) mod frameCount), exactly like the handoff's
// canvas renderer. The cast lives in IdleSpriteData.swift (generated).
//
// `IdleCreature` is the drop-in replacement for the old `CoffeeIdle`
// glyph in the notch's idle status slot: it shows one random character
// and swaps to a *different* random one every 8s (the handoff's notch
// swap cadence), so the idle state alternates between all 13 animations.

import SwiftUI
import CoreGraphics

// MARK: - Sprite model

struct IdleSprite {
    let name: String
    let fps: Double
    let palette: [String]      // hex strings, e.g. "#4FA0E8"; index 0… maps to frame digits
    let frames: [[String]]     // [frame][row], 24 rows of 24 chars
}

extension IdleSprite {
    private struct RGBA { let r, g, b: UInt8 }

    private static func parseHex(_ s: String) -> RGBA {
        var h = Substring(s)
        if h.first == "#" { h = h.dropFirst() }
        let v = UInt32(h, radix: 16) ?? 0
        return RGBA(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    /// Build one 24×24 nearest-neighbour CGImage per frame. Cheap enough
    /// (52 tiny bitmaps across the whole cast) to do without caching.
    func frameImages() -> [CGImage] {
        let pal = palette.map(Self.parseHex)
        return frames.compactMap { Self.image(for: $0, palette: pal) }
    }

    private static func image(for frame: [String], palette: [RGBA]) -> CGImage? {
        let w = 24, h = 24
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0 ..< h where y < frame.count {
            let row = Array(frame[y])
            for x in 0 ..< w where x < row.count {
                let ch = row[x]
                if ch == "." { continue }
                guard let idx = ch.hexDigitValue, idx < palette.count else { continue }
                let c = palette[idx]
                let o = (y * w + x) * 4
                bytes[o] = c.r; bytes[o + 1] = c.g; bytes[o + 2] = c.b; bytes[o + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// A uniformly-random cast index that is never equal to `current`,
    /// so successive swaps always alternate to a different character.
    static func randomIndex(excluding current: Int) -> Int {
        guard cast.count > 1 else { return 0 }
        var n = Int.random(in: 0 ..< (cast.count - 1))
        if n >= current { n += 1 }   // skip `current`, keeping the draw uniform
        return n
    }
}

// MARK: - Single-sprite renderer

/// Draws one sprite, advancing frames on its own clock. Pixels stay crisp
/// via `.interpolation(.none)` (the handoff's `image-rendering: pixelated`).
struct IdleSpriteView: View {
    let sprite: IdleSprite
    var size: CGFloat
    var running: Bool = true

    private let images: [CGImage]

    init(sprite: IdleSprite, size: CGFloat, running: Bool = true) {
        self.sprite = sprite
        self.size = size
        self.running = running
        self.images = sprite.frameImages()
    }

    @ViewBuilder
    var body: some View {
        if running {
            TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(at: 0)
        }
    }

    @ViewBuilder
    private func frame(at time: Double) -> some View {
        if images.isEmpty {
            Color.clear.frame(width: size, height: size)
        } else {
            let i = Int(time * sprite.fps) % images.count
            Image(decorative: images[i], scale: 1.0)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Idle character — random, alternating cast

/// Idle status glyph: one random character that swaps to a *different*
/// random one every `swapInterval` seconds. Replaces `CoffeeIdle`.
struct IdleCreature: View {
    var size: CGFloat = 18
    var running: Bool = true

    /// Notch swap cadence from the design handoff.
    private static let swapInterval: TimeInterval = 8

    @State private var index: Int = Int.random(in: 0 ..< IdleSprite.cast.count)
    private let swapTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        // Render larger than the requested slot size for legibility —
        // the characters read more clearly at notch scale (10% + 20%).
        IdleSpriteView(sprite: IdleSprite.cast[index], size: size * 1.32, running: running)
            .onReceive(swapTimer) { _ in
                guard running else { return }
                index = IdleSprite.randomIndex(excluding: index)
            }
            // New character → fresh frame timeline, so each one starts
            // from its first frame rather than mid-cycle.
            .id(index)
    }
}

#Preview {
    VStack(spacing: 16) {
        IdleCreature(size: 36)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 5), spacing: 12) {
            ForEach(IdleSprite.cast.indices, id: \.self) { i in
                IdleSpriteView(sprite: IdleSprite.cast[i], size: 40)
            }
        }
    }
    .padding(24)
    .background(Color.black)
}
