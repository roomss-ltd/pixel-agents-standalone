// CompactNotchView.swift — pitch-black extension of the hardware notch.
//
// The notch hardware is a rectangle of pure black (the camera cutout +
// surrounding bezel). To extend it horizontally we render a SINGLE
// continuous black bar that spans from the outer edge of the left wing
// all the way across to the outer edge of the right wing — overlapping
// the notch hardware in the middle. Both the bar and the hardware notch
// are black, so the overlap is invisible: the user sees one continuous
// "wider notch."
//
// Height is exactly the hardware notch height (no vertical extension
// below the menu bar). The bar's OUTER bottom corners are rounded so
// they read as a continuation of the notch's bottom curves; the rest
// of the bar's bottom edge is hidden behind the actual notch in the
// middle and only visible at the wings.
//
//   ┌─────────┐                       ┌─────────┐
//   │ ⚡N ✓N │ ← single bar, extends ───→ │ ☕     │
//   └─╮     ╭─┤                       ├─╮     ╭─┘
//      \   /  └────── notch zone ─────┘  \   /
//       ╰─╯                               ╰─╯
//   rounded BL outer                  rounded BR outer
//
// The left wing is 20% wider than the right (per the user's spec).

import SwiftUI

private struct LeftWingWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct RightWingWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CompactNotchView: View {
    @EnvironmentObject var engine: ActivityEngine
    @Environment(\.notchGeometry) var geometry

    /// Reports the rendered envelope size up to NotchView so the host
    /// NSPanel can size its click-through region to the visible content.
    var onSizeChange: (CGSize) -> Void = { _ in }

    @State private var leftIntrinsic: CGFloat = 0
    @State private var rightIntrinsic: CGFloat = 0

    var body: some View {
        // Exactly the hardware-notch height — zero vertical extension
        // below the menu bar. Falls back to a minimal value if no notch.
        let panelHeight: CGFloat = geometry.hasNotch ? geometry.notchHeight : 22
        // ── LENGTH KNOB ─────────────────────────────────────────────
        // Controls how wide the bar's middle zone is — i.e. how far the
        // overlay extends to the LEFT and RIGHT of the hardware notch.
        // Drop this value to shrink the overall bar; raise it to make
        // the overlay fan out further beyond the hardware notch.
        // Total visible bar = leftWing + notchSpan + rightWing.
        let notchSpan: CGFloat = 180
        // Symmetric padding so icons sit CENTERED in each wing with
        // breathing room on both sides — clear gap to the LEFT of the
        // blue badge, mirrored on the RIGHT of the cup/loader.
        let pad: CGFloat = 12
        let leftWing  = max(leftIntrinsic  + pad * 2, 28)
        let rightWing = max(rightIntrinsic + pad * 2, 28)
        // Continuous bar spans the entire range: left wing + notch + right wing.
        let barWidth = leftWing + notchSpan + rightWing
        // Centre the notch zone (middle of the bar) on the panel midX
        // (which is the hardware notch's centre).
        let visualOffset = (rightWing - leftWing) / 2
        // Click envelope must cover the bar even when wings are asymmetric.
        let envelopeWidth = max(leftWing, rightWing) * 2 + notchSpan
        // Outer corners — top corners now curve outward with a noticeable
        // radius (matches/exceeds the bottom) so the top doesn't read as
        // a sharp 90° transition; bottom curves are where the bar
        // rejoins the menu bar.
        let topR: CGFloat = 6
        let botR: CGFloat = 10

        ZStack {
            // Hidden measurement layer — renders both slots unconstrained at
            // their natural intrinsic widths, captures via PreferenceKeys.
            HStack(spacing: 0) {
                leftSlot
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: LeftWingWidthKey.self, value: g.size.width)
                        }
                    )
                rightSlot
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: RightWingWidthKey.self, value: g.size.width)
                        }
                    )
            }
            .fixedSize()
            .opacity(0)
            .allowsHitTesting(false)

            // Single continuous black bar with content overlaid.
            ZStack(alignment: .top) {
                CompactBarShape(topRadius: topR, bottomRadius: botR)
                    .fill(Color.black)
                    .frame(width: barWidth, height: panelHeight)

                // Content: each slot is CENTERED inside its wing so the
                // icons have padding on both sides — including a clear
                // gap between the blue badge and the bar's left edge.
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: pad)
                        leftSlot
                        Spacer(minLength: pad)
                    }
                    .frame(width: leftWing, height: panelHeight)

                    Color.clear.frame(width: notchSpan, height: panelHeight)

                    HStack(spacing: 0) {
                        Spacer(minLength: pad)
                        rightSlot
                        Spacer(minLength: pad)
                    }
                    .frame(width: rightWing, height: panelHeight)
                }
                .frame(width: barWidth, height: panelHeight)
            }
            .offset(x: visualOffset)
        }
        .frame(width: envelopeWidth, height: panelHeight)
        .onPreferenceChange(LeftWingWidthKey.self) { leftIntrinsic = $0 }
        .onPreferenceChange(RightWingWidthKey.self) { rightIntrinsic = $0 }
        .onChange(of: envelopeWidth) { _, newWidth in
            onSizeChange(CGSize(width: newWidth, height: panelHeight))
        }
        .onAppear {
            onSizeChange(CGSize(width: envelopeWidth, height: panelHeight))
        }
    }

    // MARK: - Left wing — slim processing + finished counters

    private var leftSlot: some View {
        HStack(spacing: 4) {
            slimBadge(color: Theme.Neon.blue,  count: inProgressCount)
            slimBadge(color: Theme.Neon.green, count: doneCount)
        }
    }

    private func slimBadge(color: Color, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.7), radius: 1.8)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.36), lineWidth: 0.5))
    }

    // MARK: - Right wing — animated activity glyph

    @ViewBuilder
    private var rightSlot: some View {
        if hasActiveSession {
            RotatingLoader(size: 18, color: Theme.Neon.blue)
        } else {
            CoffeeIdle(size: 18)
        }
    }

    // MARK: - Counts derived from engine

    private var sessions: [Session] { engine.displaySessions }

    private var hasActiveSession: Bool {
        sessions.contains {
            switch $0.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }
    }

    private var inProgressCount: Int {
        sessions.filter {
            switch $0.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }.count
    }

    /// Counter mirrors the expanded panel's green badge — only sessions
    /// that completed in this run, NOT historical jsonl files surfaced as
    /// `.done` for the OLDER list.
    private var doneCount: Int {
        sessions.filter { $0.activity == .done && !$0.isHistorical }.count
    }
}
