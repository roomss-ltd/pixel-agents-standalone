// CountBadge.swift — pill-shaped count chip used in the compact notch + expanded header.
//
// Matches `notch.jsx:80-100` exactly:
//   * 20pt high pill, padding `2 7 2 6`
//   * leading icon (●/✓/⚠) + tabular-num count
//   * tinted background + 0.5pt edge stroke
//   * font-size 11.5, font-weight 600, line-height 1, tracking 0.01em

import SwiftUI

struct CountBadge: View {
    enum Kind { case blue, green, amber }

    let kind: Kind
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            leadingGlyph
            Text("\(count)")
                .font(.system(size: countFontSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .layoutPriority(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .frame(height: Theme.Layout.countBadgeHeight)
        .background(
            Capsule(style: .continuous)
                .fill(bgColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(edgeColor, lineWidth: 0.5)
        )
        .foregroundStyle(fgColor)
    }

    private var countFontSize: CGFloat {
        if count >= 100 { return 9.5 }
        if count >= 10 { return 10.5 }
        return 11.5
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch kind {
        case .blue:
            // 6pt glowing dot — `notch.jsx:94`
            Circle()
                .fill(fgColor)
                .frame(width: 6, height: 6)
                .shadow(color: fgColor, radius: 2, x: 0, y: 0)
        case .green:
            CheckGlyph()
                .stroke(fgColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 9, height: 9)
        case .amber:
            WarnGlyph()
                .stroke(fgColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 10)
        }
    }

    private var fgColor: Color {
        switch kind {
        case .blue:  return Theme.Neon.blue
        case .green: return Theme.Neon.green
        case .amber: return Theme.Neon.amber
        }
    }

    private var bgColor: Color {
        switch kind {
        case .blue:  return Theme.Neon.blueSoft
        case .green: return Theme.Neon.greenSoft
        case .amber: return Theme.Neon.amberSoft
        }
    }

    private var edgeColor: Color {
        switch kind {
        case .blue:  return Theme.Neon.blueEdge
        case .green: return Theme.Neon.greenEdge
        case .amber: return Theme.Neon.amberEdge
        }
    }
}

// MARK: - Glyph paths (exported for reuse)

/// 16×16 viewBox check mark — matches `icons.jsx:53` (`<path d="M3 8.5l3.5 3.5L13 5"/>`).
struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16.0
        var p = Path()
        p.move(to: CGPoint(x: 3 * s, y: 8.5 * s))
        p.addLine(to: CGPoint(x: 6.5 * s, y: 12 * s))
        p.addLine(to: CGPoint(x: 13 * s, y: 5 * s))
        return p
    }
}

/// 16×16 viewBox warn triangle — matches `icons.jsx:46`.
struct WarnGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16.0
        var p = Path()
        p.move(to: CGPoint(x: 8 * s, y: 2.5 * s))
        p.addLine(to: CGPoint(x: 14.5 * s, y: 13.5 * s))
        p.addLine(to: CGPoint(x: 1.5 * s, y: 13.5 * s))
        p.closeSubpath()
        // exclamation stroke (drawn over the same path)
        p.move(to: CGPoint(x: 8 * s, y: 6.5 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 10 * s))
        return p
    }
}

#Preview {
    HStack(spacing: 8) {
        CountBadge(kind: .blue, count: 2)
        CountBadge(kind: .green, count: 12)
        CountBadge(kind: .amber, count: 1)
    }
    .padding()
    .background(Color.black)
}
