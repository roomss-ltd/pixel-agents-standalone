// NotchShape.swift — pearl + expanded panel geometries for the notch UI.

import SwiftUI

/// Side of the notch the pearl is on.
enum PearlSide { case left, right }

/// A rounded "pearl" that sits below the notch on either side.
/// Top-inner corner curves INWARD (toward the notch's hardware corner)
/// so it visually merges with the notch's bottom edge.
///
/// rect.maxY is the pearl's bottom; rect.minY is its top (which rests
/// just below the notch). The OUTER side (`side == .left` => the LEFT edge,
/// `side == .right` => the RIGHT edge) is fully rounded with `outerCornerRadius`.
/// The INNER side (the notch-facing edge) sweeps in with `innerCornerRadius`.
struct PearlShape: Shape {
    let side: PearlSide
    let outerCornerRadius: CGFloat
    let innerCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let outer = outerCornerRadius
        let inner = innerCornerRadius
        var path = Path()

        switch side {
        case .left:
            // Path traversal (clockwise from top-outer-left):
            // top-left (outer) → top-right (inner, sweeps inward) →
            // bottom-right (inner) → bottom-left (outer)
            path.move(to: CGPoint(x: rect.minX + outer, y: rect.minY))
            // top edge to inner curve start
            path.addLine(to: CGPoint(x: rect.maxX - inner, y: rect.minY))
            // inner top corner: curves inward — control near the inner-top-corner of rect
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + inner),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            // inner right edge (only as long as the pearl is taller than 2*inner)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inner))
            // inner bottom corner
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - inner, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            // bottom edge
            path.addLine(to: CGPoint(x: rect.minX + outer, y: rect.maxY))
            // bottom-left (outer)
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - outer),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            // outer left edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + outer))
            // top-left (outer)
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + outer, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )

        case .right:
            // Mirror: outer side is the right edge, inner side is the left edge.
            path.move(to: CGPoint(x: rect.maxX - outer, y: rect.minY))
            // top edge to inner (left) curve start
            path.addLine(to: CGPoint(x: rect.minX + inner, y: rect.minY))
            // inner top-left curve
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + inner),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            // inner left edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inner))
            // inner bottom-left curve
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + inner, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            // bottom edge
            path.addLine(to: CGPoint(x: rect.maxX - outer, y: rect.maxY))
            // bottom-right (outer)
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - outer),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            // outer right edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + outer))
            // top-right (outer)
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - outer, y: rect.minY),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }

        return path
    }
}

/// The expanded panel that drops down from the notch.
/// Top edge has the same notch carve as the OS notch (so the panel
/// hugs the notch's bottom edge). Bottom corners are fully rounded.
struct ExpandedPanelShape: Shape {
    /// Width of the OS notch in points. 0 on non-notched Macs (panel becomes a plain rounded rect).
    let notchWidth: CGFloat
    /// Corner radius where the notch carve meets the panel's top edge.
    let notchCornerRadius: CGFloat
    /// Bottom corner radius of the panel.
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = bottomCornerRadius
        let nw = notchWidth
        let nr = notchCornerRadius
        let centerX = rect.midX

        // start: top-left corner of panel, after the carve
        if nw > 0 {
            let notchLeft  = centerX - nw / 2
            let notchRight = centerX + nw / 2

            // top-left of panel (left of the notch carve)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: notchLeft - nr, y: rect.minY))
            // sweep INTO the notch's bottom-left corner
            path.addQuadCurve(
                to: CGPoint(x: notchLeft, y: rect.minY + nr),
                control: CGPoint(x: notchLeft, y: rect.minY)
            )
            // bottom of the notch (straight)
            path.addLine(to: CGPoint(x: notchRight, y: rect.minY + nr))
            // sweep OUT of the notch's bottom-right corner
            path.addQuadCurve(
                to: CGPoint(x: notchRight + nr, y: rect.minY),
                control: CGPoint(x: notchRight, y: rect.minY)
            )
            // top-right of panel
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            // No notch — just a plain rectangle top.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

#Preview {
    VStack(spacing: 8) {
        HStack(spacing: 200) {  // 200pt spacer = where the notch is
            PearlShape(side: .left, outerCornerRadius: 13, innerCornerRadius: 10)
                .fill(Theme.panelBg)
                .frame(width: 56, height: 26)
            PearlShape(side: .right, outerCornerRadius: 13, innerCornerRadius: 10)
                .fill(Theme.panelBg)
                .frame(width: 56, height: 26)
        }
        ExpandedPanelShape(notchWidth: 200, notchCornerRadius: 10, bottomCornerRadius: 12)
            .fill(Theme.panelBg)
            .frame(width: 340, height: 200)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
