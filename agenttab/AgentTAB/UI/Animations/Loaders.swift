// Loaders.swift — SwiftUI ports of the ldrs.com variants the Hammerspoon
// implementation (and the React design canvas) cycle through.
//
// Each loader reads `currentColor` via `.foregroundStyle(color)` so a parent
// can recolor without mutating the loader. `RotatingLoader` swaps variants
// every 15s — same as `notch.jsx:RotatingLoader`.

import SwiftUI

// MARK: - Variant catalog

enum LoaderVariant: String, CaseIterable {
    case dotSpinner    = "dot-spinner"
    case quantum       = "quantum"
    case cardio        = "cardio"
    case trio          = "trio"
    case chaoticOrbit  = "chaotic-orbit"
    case grid          = "grid"
    case reuleaux      = "reuleaux"
    case change        = "change"
}

// MARK: - DotSpinner — 8 dots pulsing around a circle

struct DotSpinnerLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.0   // total cycle (loaders.jsx:14, speed * 1.111)

            ZStack {
                ForEach(0..<8) { i in
                    let phase = ((t / period) + Double(i) / 8.0).truncatingRemainder(dividingBy: 1)
                    let scale = 0.5 + 0.5 * abs(sin(phase * .pi))
                    Circle()
                        .fill(color)
                        .frame(width: size * 0.2, height: size * 0.2)
                        .opacity(0.5 + 0.5 * scale)
                        .scaleEffect(scale)
                        .offset(y: -size * 0.4)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Quantum — two concentric arcs spinning opposite directions

struct QuantumLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let outerAngle = (t * 360 / 1.75).truncatingRemainder(dividingBy: 360)
            let innerAngle = -(t * 360 / 1.75).truncatingRemainder(dividingBy: 360)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(color.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(outerAngle))

                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(color.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size * 0.56, height: size * 0.56)
                    .rotationEffect(.degrees(innerAngle))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Trio — three vertical bars bouncing

struct TrioLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.3

            HStack(spacing: size * 0.12) {
                ForEach(0..<3) { i in
                    let delay = Double(i) * 0.2
                    let phase = ((t + delay) / period).truncatingRemainder(dividingBy: 1)
                    // 40% of cycle bouncing up, rest scaled down (loaders.jsx:101)
                    let scale: CGFloat = phase < 0.4
                        ? 0.4 + 0.6 * (phase / 0.4)
                        : 1.0 - 0.6 * ((phase - 0.4) / 0.6)
                    Capsule()
                        .fill(color)
                        .frame(width: size * 0.22, height: size * 0.6)
                        .scaleEffect(y: scale, anchor: .bottom)
                }
            }
            .frame(width: size, height: size * 0.6)
        }
    }
}

// MARK: - ChaoticOrbit — two dots orbiting in counter-phase

struct ChaoticOrbitLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.5
            let p = (t / period).truncatingRemainder(dividingBy: 1)
            // Whole disc slowly rotates while the two dots oscillate on
            // a horizontal axis with phase-offset scaling.
            let spin = (t * 360 / (period * 1.667)).truncatingRemainder(dividingBy: 360)
            ZStack {
                orbitingDot(phase: p)
                orbitingDot(phase: (p + 0.5).truncatingRemainder(dividingBy: 1))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin))
        }
    }

    private func orbitingDot(phase p: Double) -> some View {
        let cos2  = cos(p * 2 * .pi)
        let sin2  = sin(p * 2 * .pi)
        let x     = CGFloat(0.25 * cos2) * size
        let scale = CGFloat(0.5 + 0.5 * sin2)
        let alpha = 0.35 + 0.65 * max(0, 0.5 + 0.5 * sin2)
        return Circle()
            .fill(color)
            .frame(width: size * 0.4, height: size * 0.4)
            .scaleEffect(scale)
            .opacity(alpha)
            .offset(x: x)
    }
}

// MARK: - Grid — 3×3 pulse cascade

struct GridLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.2
            let dot = size * 0.22
            let gap = size * 0.12

            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { col in
                            let i = row * 3 + col
                            let offset = Double(i) / 9.0
                            let phase = ((t / period) + offset)
                                .truncatingRemainder(dividingBy: 1)
                            let s = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                            Circle()
                                .fill(color)
                                .frame(width: dot, height: dot)
                                .scaleEffect(0.5 + 0.5 * s)
                                .opacity(0.4 + 0.6 * s)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Reuleaux — rotating equilateral curved triangle

struct ReuleauxLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let rotation = (t * 360 / 1.5).truncatingRemainder(dividingBy: 360)
            ReuleauxShape()
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
        }
    }
}

private struct ReuleauxShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = min(rect.width, rect.height) / 2 * 0.92
        let cx: CGFloat = rect.midX
        let cy: CGFloat = rect.midY
        var v: [CGPoint] = []
        for i in 0..<3 {
            let a: Double = Double(i) * 2.0 * .pi / 3.0 - .pi / 2.0
            let x: CGFloat = cx + radius * CGFloat(cos(a))
            let y: CGFloat = cy + radius * CGFloat(sin(a))
            v.append(CGPoint(x: x, y: y))
        }
        var p = Path()
        p.move(to: v[0])
        for i in 0..<3 {
            let center = v[(i + 2) % 3]
            let start = v[i]
            let end   = v[(i + 1) % 3]
            let r = sqrt(pow(start.x - center.x, 2) + pow(start.y - center.y, 2))
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let endAngle   = atan2(end.y - center.y, end.x - center.x)
            p.addArc(
                center: center,
                radius: r,
                startAngle: .radians(startAngle),
                endAngle: .radians(endAngle),
                clockwise: false
            )
        }
        return p
    }
}

// MARK: - Change — two rounded squares spinning in opposite directions

struct ChangeLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let rotation = (t * 360 / 2.0).truncatingRemainder(dividingBy: 360)
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: size * 0.7, height: size * 0.7)
                    .rotationEffect(.degrees(rotation))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(color.opacity(0.65), lineWidth: 1.5)
                    .frame(width: size * 0.7, height: size * 0.7)
                    .rotationEffect(.degrees(-rotation + 45))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Rotating loader — chaos pattern, rotating monotone palette
//
// Per the user's spec the notch's active-processing animation is the
// `chaos-rotate` Pixel Loops variant: all 9 cells of the 3×3 grid
// flicker independently with hash-based randomness so the pattern is
// "forever different" — it never repeats. The variant is pinned; only
// the palette cycles, stepping through the 6 monotone accents (blue,
// pink, white, purple, cyan, dark blue) every `intervalSeconds`.
//
// The `color` parameter is retained for source compatibility with the
// previous API but is ignored: Pixel Loops define their own palettes.

struct RotatingLoader: View {
    var size: CGFloat = 18
    /// Retained for API compat with the old ldrs-based loader. Pixel
    /// Loops drive their own monotone palettes, so this is ignored.
    var color: Color = Theme.Neon.blue
    var intervalSeconds: Double = Theme.Animations.loaderRotationSeconds
    var running: Bool = true

    @State private var paletteIndex: Int = 0

    private var palette: PixelLoopPalette {
        PixelLoopPalette.allCases[paletteIndex % PixelLoopPalette.allCases.count]
    }

    /// Crossfade duration when stepping from one palette to the next.
    /// Long enough that the change reads as a slow tint shift, not a
    /// hard cut, but short relative to `intervalSeconds` so most of the
    /// time the loop sits firmly in one accent.
    private static let crossfadeSeconds: Double = 1.6

    var body: some View {
        PixelLoopView(variant: .chaosRotate,
                      palette: palette,
                      coreOverride: palette.core,
                      glowOverride: palette.glow,
                      size: size,
                      running: running,
                      paletteCrossfadeDuration: Self.crossfadeSeconds)
            .frame(width: size, height: size)
            .onAppear {
                // Stagger so multiple RotatingLoaders mounted simultaneously
                // don't pick the same starting palette.
                paletteIndex = Int.random(in: 0..<PixelLoopPalette.allCases.count)
            }
            .task(id: running) {
                guard running else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    paletteIndex = (paletteIndex + 1) % PixelLoopPalette.allCases.count
                }
            }
    }
}

#Preview {
    HStack(spacing: 24) {
        RotatingLoader(size: 28, intervalSeconds: 1.5)
        RotatingLoader(size: 28, intervalSeconds: 1.5)
        RotatingLoader(size: 28, intervalSeconds: 1.5)
    }
    .padding()
    .background(Color.black)
}
