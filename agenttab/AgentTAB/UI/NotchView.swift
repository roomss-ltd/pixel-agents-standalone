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
        // Ratio used for the morph animation — the expanded view's
        // insertion scale starts at the COMPACT bar's actual size, so
        // the morph reads as the bar growing into the panel rather than
        // appearing from nowhere.
        let morphRatio: CGFloat = max(compactSize.width / max(expandedSize.width, 1), 0.18)

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
                        // Grows from the compact bar's silhouette to its
                        // full size, anchored at the top so the bottom
                        // edge sweeps down. Pure scale on insertion so
                        // it stays fully opaque — covers the compact
                        // bar without alpha-blend artefacts.
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: morphRatio, anchor: .top),
                                removal: .scale(scale: morphRatio, anchor: .top)
                                    .combined(with: .opacity)
                            )
                        )
                        .zIndex(1)
                    } else {
                        CompactNotchView(onSizeChange: { size in
                            compactSize = size
                            onSizeChange(size)
                        })
                        // Compact stays at full size during a transition
                        // out — only its alpha drops. The expanded view
                        // (z-index 1) covers it as it grows, so the user
                        // never sees the compact bar shrink "inward."
                        .transition(.opacity)
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
