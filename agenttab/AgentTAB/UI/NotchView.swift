// NotchView.swift — top-level orchestrator for the notch UI.
//
// Two visible states:
//
//   compact ─hover────▶ expanded ─unhover (unpinned)─▶ compact
//                       ─pin click─▶ stays expanded
//                       ─click outside / Esc / chevron─▶ compact
//
// Hover detection is shape-bounded via `.contentShape(...)`: hover only
// fires when the cursor is inside the actual visible black surface
// (CompactBarShape or DropPanelShape), not the rectangular bounding box
// the views occupy.
//
// `manualCollapse` is set when the user explicitly collapses (chevron /
// Esc / click-outside). While set, the panel stays compact even if the
// cursor is over its area — preventing immediate re-expansion. Cleared
// the moment the cursor leaves the compact surface.
//
// `onSizeChange` reports the active rendered size so the host NSPanel
// can size its live click-through region accordingly.

import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine

    @State private var isHovered: Bool = false
    @State private var isPinned: Bool = false
    @State private var manualCollapse: Bool = false
    @State private var compactSize: CGSize = CGSize(
        width: Theme.Layout.compactWidth,
        height: Theme.Layout.compactHeight
    )
    @State private var expandedSize: CGSize = CGSize(
        width: Theme.Layout.expandedWidth,
        height: Theme.Layout.expandedHeight
    )

    var onSizeChange: (CGSize) -> Void = { _ in }

    enum Phase: Equatable { case compact, expanded }

    private var phase: Phase {
        if manualCollapse { return .compact }
        return (isHovered || isPinned) ? .expanded : .compact
    }

    var body: some View {
        // The expanded view's insertion starts at the compact bar's
        // EXACT size — non-uniform scale so width AND height match
        // compactSize precisely. Combined with `.identity` on compact,
        // the user sees one continuous bar growing into the panel
        // rather than a second component appearing on top.
        let xRatio: CGFloat = max(compactSize.width  / max(expandedSize.width,  1), 0.18)
        let yRatio: CGFloat = max(compactSize.height / max(expandedSize.height, 1), 0.10)

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                ZStack(alignment: .top) {
                    if phase == .expanded {
                        ExpandedView(
                            isPinned: $isPinned,
                            onCollapse: collapse,
                            onSizeChange: { size in
                                expandedSize = size
                                onSizeChange(size)
                            }
                        )
                        // Non-uniform scale anchored at the top: at t=0
                        // the panel renders at exactly compactSize and
                        // grows from there to (expandedWidth, expandedHeight).
                        .transition(
                            .modifier(
                                active: ScaleToFitModifier(x: xRatio, y: yRatio, anchor: .top),
                                identity: ScaleToFitModifier(x: 1, y: 1, anchor: .top)
                            )
                        )
                        .zIndex(1)
                    } else {
                        CompactNotchView(onSizeChange: { size in
                            compactSize = size
                            onSizeChange(size)
                        })
                        // Compact swaps out instantly the moment phase
                        // flips — the expanded view appears at the same
                        // pixel size at t=0, so the user perceives a
                        // single bar morphing rather than a fade.
                        .transition(.identity)
                        .zIndex(0)
                    }
                }
                // Strictly shape-bounded hit area — hover fires only when
                // the cursor is over the actual visible black surface,
                // never over the transparent corner pixels of the
                // bounding rect.
                .contentShape(currentHitShape)
                .onHover { hovering in
                    isHovered = hovering
                    if !hovering { manualCollapse = false }
                }
                Spacer()
            }
            // No top padding — each phase view extends ITS OWN black background
            // up by `notchHeight` so it merges with the hardware notch.
            Spacer()
        }
        .animation(Theme.Animations.notch, value: phase)
        .onChange(of: phase) { _, newValue in
            onSizeChange(currentSize(for: newValue))
        }
        .onAppear {
            onSizeChange(currentSize(for: phase))
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentTabRequestCollapse)) { _ in
            collapse()
        }
    }

    private func collapse() {
        isPinned = false
        isHovered = false
        // Suppress re-expansion until the cursor leaves the compact area
        // — fixes the "click chevron, panel collapses then immediately
        // re-opens because cursor is still over the compact surface".
        manualCollapse = true
    }

    private func currentSize(for phase: Phase) -> CGSize {
        switch phase {
        case .compact:  return compactSize
        case .expanded: return expandedSize
        }
    }

    /// Hit-test shape for the current phase — used by `.contentShape` so
    /// `.onHover` only fires on the visible black surface.
    private var currentHitShape: AnyShape {
        switch phase {
        case .compact:
            return AnyShape(CompactBarShape(topRadius: 6, bottomRadius: 10))
        case .expanded:
            return AnyShape(DropPanelShape(cornerRadius: Theme.Layout.expandedCornerRadius))
        }
    }
}

extension Notification.Name {
    /// Posted by NotchPanel when the user clicks outside the live region or
    /// presses Esc while the panel is up.
    static let agentTabRequestCollapse = Notification.Name("AgentTAB.RequestCollapse")
}

/// Custom transition modifier — non-uniform scaleEffect with anchor.
/// Lets the expanded view enter at the compact bar's exact dimensions
/// (so width AND height match), instead of a uniform `.scale` which
/// would force the height to be (expandedHeight × widthRatio).
private struct ScaleToFitModifier: ViewModifier {
    var x: CGFloat
    var y: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content.scaleEffect(x: x, y: y, anchor: anchor)
    }
}
