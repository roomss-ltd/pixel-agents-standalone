// NotchView.swift — top-level orchestrator for the notch UI.
//
// Two visible states:
//
//   compact ─hover────▶ expanded ─unhover (unpinned)─▶ compact
//                       ─pin click─▶ stays expanded
//                       ─click outside / Esc─▶ compact (unpins)
//
// `expanded` is the dynamic-height pinned panel showing every running agent.
// We don't gate it behind an intermediate "hover preview" — the user wants
// the whole picture as soon as they reach for the notch.
//
// Phase swaps animate as a scale-from-top: the expanded panel grows out of
// the small notch silhouette rather than cross-fading.
//
// `onSizeChange` reports the active rendered size so the host NSPanel can
// size its live click-through region accordingly. Each phase view measures
// its own intrinsic size and routes it through here.

import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine

    @State private var isHovered: Bool = false
    @State private var isPinned: Bool = false
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
        (isHovered || isPinned) ? .expanded : .compact
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        .transition(
                            .asymmetric(
                                // Grow out of the compact notch silhouette,
                                // anchored to the top so the bottom edge falls
                                // down rather than flying in from the middle.
                                insertion: .scale(scale: 0.32, anchor: .top)
                                    .combined(with: .opacity),
                                removal: .scale(scale: 0.32, anchor: .top)
                                    .combined(with: .opacity)
                            )
                        )
                    } else {
                        CompactNotchView(onSizeChange: { size in
                            compactSize = size
                            onSizeChange(size)
                        })
                        .transition(.opacity)
                    }
                }
                .background(HoverTracker(onHover: { hovering in
                    isHovered = hovering
                }))
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
    }

    private func currentSize(for phase: Phase) -> CGSize {
        switch phase {
        case .compact:  return compactSize
        case .expanded: return expandedSize
        }
    }
}

extension Notification.Name {
    /// Posted by NotchPanel when the user clicks outside the live region or
    /// presses Esc while the panel is up.
    static let agentTabRequestCollapse = Notification.Name("AgentTAB.RequestCollapse")
}
