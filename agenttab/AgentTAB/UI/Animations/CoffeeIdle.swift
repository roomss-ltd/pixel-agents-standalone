import SwiftUI

struct CoffeeIdle: View {
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Static cup body — paths from icons.lua:13
                CoffeeBody().stroke(
                    Color.white.opacity(0.62),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )

                // Three steam wisps with phase-shifted animation
                SmokeWisp(pathIndex: 0, phase: phase(t, offset: 0.0))
                SmokeWisp(pathIndex: 1, phase: phase(t, offset: 0.33))
                SmokeWisp(pathIndex: 2, phase: phase(t, offset: 0.66))
            }
            .frame(width: size, height: size)
        }
    }

    private func phase(_ t: TimeInterval, offset: Double) -> Double {
        let p = ((t / Theme.Animations.coffeeSteamPeriod) + offset).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }
}

private struct CoffeeBody: Shape {
    func path(in rect: CGRect) -> Path {
        // viewBox 24×24 — paths from icons.lua:13 (cup outline only, simplified)
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // Cup body rectangle + curved bottom
        path.move(to: CGPoint(x: 4 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 15 * s))
        path.addArc(center: CGPoint(x: 12 * s, y: 15 * s), radius: 6 * s,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 4 * s, y: 8 * s))
        path.closeSubpath()
        // Handle (semicircle to the right)
        path.move(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 8 * s))
        path.addArc(center: CGPoint(x: 19 * s, y: 12 * s), radius: 4 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: 18 * s, y: 16 * s))
        return path
    }
}

private struct SmokeWisp: View {
    let pathIndex: Int
    let phase: Double

    var body: some View {
        // Opacity wave keyframes from styles.lua:255 — coffeeSteam
        // 0% → 18%: opacity 0 → 0.24
        // 18% → 42%: opacity 0.24 → 0.76 (peak)
        // 42% → 78%: opacity 0.76 → 0.08
        // 78% → 100%: opacity 0.08 → 0
        let opacity: Double = {
            switch phase {
            case 0..<0.18:   return phase / 0.18 * 0.24
            case 0.18..<0.42: return 0.24 + (phase - 0.18) / 0.24 * (0.76 - 0.24)
            case 0.42..<0.78: return 0.76 - (phase - 0.42) / 0.36 * (0.76 - 0.08)
            case 0.78..<1.0:  return 0.08 - (phase - 0.78) / 0.22 * 0.08
            default:          return 0
            }
        }()

        // Vertical translate: +3 (start) → -9 (end), 12pt total over the cycle
        let dy: CGFloat = -CGFloat(phase * 12 - 3)

        // Stroke widths per wisp (from styles.lua:243-253)
        let strokeWidth: CGFloat = {
            switch pathIndex {
            case 1:  return 2.15  // middle wisp — heaviest
            case 0:  return 1.45  // left
            default: return 1.55  // right
            }
        }()

        SteamPath(index: pathIndex)
            .stroke(
                Color.white.opacity(0.62 * opacity),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .offset(y: dy)
    }
}

private struct SteamPath: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // Three wisp paths from icons.lua:13:
        //   1: M7.1 7.1 C 4.2 5.2, 10.1 5.6, 7.4 4.6
        //   2: M11 7.1 C 8.1 5.1, 14 3.9, 11.2 1.3
        //   3: M14.9 7.1 C 12 5.2, 17.8 5.6, 15 4.6
        switch index {
        case 0:
            path.move(to: CGPoint(x: 7.1 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 7.4 * s, y: 4.6 * s),
                control1: CGPoint(x: 4.2 * s, y: 5.2 * s),
                control2: CGPoint(x: 10.1 * s, y: 5.6 * s)
            )
        case 1:
            path.move(to: CGPoint(x: 11 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 11.2 * s, y: 1.3 * s),
                control1: CGPoint(x: 8.1 * s, y: 5.1 * s),
                control2: CGPoint(x: 14 * s, y: 3.9 * s)
            )
        case 2:
            path.move(to: CGPoint(x: 14.9 * s, y: 7.1 * s))
            path.addCurve(
                to: CGPoint(x: 15 * s, y: 4.6 * s),
                control1: CGPoint(x: 12 * s, y: 5.2 * s),
                control2: CGPoint(x: 17.8 * s, y: 5.6 * s)
            )
        default:
            break
        }
        return path
    }
}

#Preview {
    CoffeeIdle(size: 28)
        .padding()
        .background(Color.black)
}
