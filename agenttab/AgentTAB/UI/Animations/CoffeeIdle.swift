// CoffeeIdle.swift — exact port of the Hammerspoon `coffee` glyph
// used by the Zellij integration.
//
// Source paths: claude-tab-status/hammerspoon/webview/icons.lua:13
//   • cup body:  M4 8 h14 v7 a6 6 0 0 1 -6 6 H10 a6 6 0 0 1 -6 -6 Z
//   • handle:    M18 8 h1 a4 4 0 1 1 0 8 h-1
//   • top rim:   M6 8 h10
//   • smoke 1:   M7.1 7.1 C 4.2 5.2, 10.1 5.6, 7.4 4.6
//   • smoke 2:   M11 7.1  C 8.1 5.1, 14 3.9,  11.2 1.3
//   • smoke 3:   M14.9 7.1 C 12 5.2,  17.8 5.6, 15 4.6
//
// Animation: claude-tab-status/hammerspoon/webview/styles.lua:255-281
// (`@keyframes coffeeSteam`, period 4.8s) ported as a continuous
// TimelineView with the keyframed opacity / Y-translate / dashoffset.

import SwiftUI

struct CoffeeIdle: View {
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = Theme.Animations.coffeeSteamPeriod
            let strokeScale = max(size / 24, 0.4)

            ZStack {
                CupShape()
                    .stroke(
                        Color.white.opacity(0.62),
                        style: StrokeStyle(
                            lineWidth: 1.65 * strokeScale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                // Three wisps, each 1/3 of the cycle out of phase so
                // they stagger like the original three-delay rule.
                ForEach(0..<3, id: \.self) { i in
                    SmokeWisp(
                        index: i,
                        phase: phase(for: i, t: t, period: period),
                        strokeScale: strokeScale
                    )
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func phase(for index: Int, t: TimeInterval, period: Double) -> Double {
        let offset = Double(index) / 3.0
        let p = ((t / period) + offset).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }
}

// MARK: - Cup body + handle + top rim

private struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()

        // Body: M4 8 h14 v7 a6 6 0 0 1 -6 6 H10 a6 6 0 0 1 -6 -6 Z
        path.move(to: CGPoint(x: 4 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 15 * s))
        // Bottom-right corner — quarter arc from (18, 15) to (12, 21).
        path.addArc(
            center: CGPoint(x: 12 * s, y: 15 * s),
            radius: 6 * s,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 10 * s, y: 21 * s))
        // Bottom-left corner — quarter arc from (10, 21) to (4, 15).
        path.addArc(
            center: CGPoint(x: 10 * s, y: 15 * s),
            radius: 6 * s,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()

        // Handle: M18 8 h1 a4 4 0 1 1 0 8 h-1
        // SVG `sweep=1` = clockwise on a y-down canvas → the arc
        // bulges out to the RIGHT (away from the cup body), passing
        // through (23, 12).
        path.move(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 8 * s))
        path.addArc(
            center: CGPoint(x: 19 * s, y: 12 * s),
            radius: 4 * s,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 18 * s, y: 16 * s))

        // Top rim: M6 8 h10
        path.move(to: CGPoint(x: 6 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 16 * s, y: 8 * s))

        return path
    }
}

// MARK: - Steam wisps

private struct SmokeWisp: View {
    let index: Int            // 0, 1, 2
    let phase: Double         // 0..<1 within the cycle
    let strokeScale: CGFloat  // size / 24

    var body: some View {
        let opacity = wispOpacity(p: phase)
        let dy = wispDy(p: phase) * strokeScale
        let progress = wispProgress(p: phase)
        let lineWidth = wispLineWidth() * strokeScale

        SteamPath(index: index)
            .trim(from: 0, to: progress)
            .stroke(
                // styles.lua opacity peaks at 0.76 and the layer also
                // multiplies by .coffee-smoke's base opacity 0.52.
                // Combine to keep peaks visible without saturating.
                Color.white.opacity(0.62 * opacity),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .offset(y: dy)
    }

    /// Opacity at each keyframe — `0% → 18% → 42% → 78% → 100%`
    /// matches the source `@keyframes coffeeSteam`.
    private func wispOpacity(p: Double) -> Double {
        switch p {
        case 0..<0.18:    return p / 0.18 * 0.24
        case 0.18..<0.42: return 0.24 + (p - 0.18) / 0.24 * (0.76 - 0.24)
        case 0.42..<0.78: return 0.76 - (p - 0.42) / 0.36 * (0.76 - 0.08)
        case 0.78..<1.0:  return 0.08 - (p - 0.78) / 0.22 * 0.08
        default:          return 0
        }
    }

    /// Vertical translate at each keyframe (viewBox units, scaled to
    /// pt by `strokeScale` in `body`).
    private func wispDy(p: Double) -> CGFloat {
        let y: Double
        switch p {
        case 0..<0.18:    y = 3 + (p / 0.18) * (1 - 3)
        case 0.18..<0.42: y = 1 + (p - 0.18) / 0.24 * (-3 - 1)
        case 0.42..<0.78: y = -3 + (p - 0.42) / 0.36 * (-7 - -3)
        case 0.78..<1.0:  y = -7 + (p - 0.78) / 0.22 * (-9 - -7)
        default:          y = -9
        }
        return CGFloat(y)
    }

    /// Stroke trim end — mirrors `stroke-dasharray:9; stroke-dashoffset 9→0`.
    /// At each keyframe the visible portion of the wisp is
    /// `(9 - dashoffset) / 9`, so the wisp draws progressively from
    /// the cup outward.
    private func wispProgress(p: Double) -> CGFloat {
        switch p {
        case 0..<0.18:    return CGFloat(p / 0.18 * 0.31)
        case 0.18..<0.42: return CGFloat(0.31 + (p - 0.18) / 0.24 * (0.69 - 0.31))
        case 0.42..<0.78: return CGFloat(0.69 + (p - 0.42) / 0.36 * (1.0 - 0.69))
        default:          return 1.0
        }
    }

    /// Per-wisp stroke widths from `styles.lua:243-253`.
    private func wispLineWidth() -> CGFloat {
        switch index {
        case 0:  return 1.45
        case 1:  return 2.15
        case 2:  return 1.55
        default: return 1.65
        }
    }
}

private struct SteamPath: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        switch index {
        case 0:
            // M7.1 7.1 C 4.2 5.2, 10.1 5.6, 7.4 4.6
            path.move(to: CGPoint(x: 7.1 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 7.4 * s, y: 4.6 * s),
                control1: CGPoint(x: 4.2 * s, y: 5.2 * s),
                control2: CGPoint(x: 10.1 * s, y: 5.6 * s)
            )
        case 1:
            // M11 7.1 C 8.1 5.1, 14 3.9, 11.2 1.3
            path.move(to: CGPoint(x: 11 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 11.2 * s, y: 1.3 * s),
                control1: CGPoint(x: 8.1 * s, y: 5.1 * s),
                control2: CGPoint(x: 14 * s, y: 3.9 * s)
            )
        default:
            // M14.9 7.1 C 12 5.2, 17.8 5.6, 15 4.6
            path.move(to: CGPoint(x: 14.9 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 15 * s, y: 4.6 * s),
                control1: CGPoint(x: 12 * s, y: 5.2 * s),
                control2: CGPoint(x: 17.8 * s, y: 5.6 * s)
            )
        }
        return path
    }
}

#Preview {
    CoffeeIdle(size: 28)
        .padding()
        .background(Color.black)
}
