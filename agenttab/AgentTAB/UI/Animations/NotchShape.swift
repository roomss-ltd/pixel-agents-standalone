// NotchShape.swift — geometries used by the AgentTab UI.
//
// All three panel sizes (compact 230×34, hover 360×86, expanded 720×460)
// share the same shape pattern: a flat top edge that meets the hardware
// notch, plus rounded bottom corners. There is no carve in the panel
// itself — the carve IS the hardware notch above it; the panel just hangs
// flush below.
//
// Mirrors the React prototype exactly:
//   * `borderRadius: "0 0 16px 16px"` for compact (`notch.jsx:141`)
//   * `borderRadius: "0 0 20px 20px"` for hover  (`notch.jsx:178`)
//   * `borderRadius: "0 0 22px 22px"` for expanded (`notch.jsx:316`)

import SwiftUI

/// Flat top, rounded bottom corners.
struct DropPanelShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

/// Compact-bar shape used by the notch overlay.
///
/// The TOP corners flare OUTWARD with concave/inverted curves so the bar
/// reads as "morphing into the end of the screen": the top edge extends
/// full-width to the screen edges, and the body narrows down via gentle
/// inward-curving shoulders. The BOTTOM corners are normal convex
/// rounds where the bar rejoins the menu bar.
///
///   ╲                       ╱       <- top flares outward
///    ╲_____________________╱
///    |                     |        <- straight body sides
///    ╲                     ╱        <- convex bottom rounds
///     ╲___________________╱
struct CompactBarShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let maxTR = min(rect.width / 4, rect.height)
        let maxBR = min(rect.width / 4, rect.height / 2)
        let tR = max(0, min(topRadius, maxTR))
        let bR = max(0, min(bottomRadius, maxBR))

        var path = Path()
        // CW from top-left of frame.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Full-width top edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right inverted shoulder — curves DOWN-LEFT into the body.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR, y: rect.minY + tR),
            control: CGPoint(x: rect.maxX - tR, y: rect.minY)
        )
        // Right body edge.
        path.addLine(to: CGPoint(x: rect.maxX - tR, y: rect.maxY - bR))
        // Bottom-right convex round.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR - bR, y: rect.maxY),
            control: CGPoint(x: rect.maxX - tR, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.minX + tR + bR, y: rect.maxY))
        // Bottom-left convex round.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tR, y: rect.maxY - bR),
            control: CGPoint(x: rect.minX + tR, y: rect.maxY)
        )
        // Left body edge.
        path.addLine(to: CGPoint(x: rect.minX + tR, y: rect.minY + tR))
        // Top-left inverted shoulder — curves UP-LEFT to the frame corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + tR, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Left half of the compact panel: flat top, flat right edge (the inner edge
/// that meets the notch hardware), rounded only at the bottom-left.
struct LeftWingShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Mirror of `LeftWingShape` for the right side of the notch.
struct RightWingShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Backwards-compat aliases

/// Some legacy call sites still reference `ExpandedPanelShape`. Provide a
/// thin shim so they keep compiling — internally it's just `DropPanelShape`.
struct ExpandedPanelShape: Shape {
    let notchWidth: CGFloat
    let notchCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        DropPanelShape(cornerRadius: bottomCornerRadius).path(in: rect)
    }
}

#Preview {
    VStack(spacing: 16) {
        DropPanelShape(cornerRadius: 16)
            .fill(Color.black)
            .frame(width: 230, height: 34)
        DropPanelShape(cornerRadius: 20)
            .fill(Color.black)
            .frame(width: 360, height: 86)
        DropPanelShape(cornerRadius: 22)
            .fill(Color.black)
            .frame(width: 480, height: 200)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
