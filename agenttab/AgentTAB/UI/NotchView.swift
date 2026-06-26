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

import AppKit
import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine

    @State private var isHovered: Bool = false
    @State private var isPinned: Bool = false
    @State private var manualCollapse: Bool = false
    /// True while an NSMenu (e.g. the per-row priority dropdown, the
    /// footer "⋯" menu) is open. The menu popup is a separate window
    /// that lives OUTSIDE the panel, so the cursor moving onto it would
    /// otherwise fire `.onHover(false)` and collapse the panel out from
    /// under the user. While this is set we pin the phase to expanded
    /// and ignore hover changes entirely.
    @State private var isMenuOpen: Bool = false
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
        // A menu open over the panel must never let it collapse — the
        // user is mid-interaction with a dropdown that belongs to it.
        if isMenuOpen { return .expanded }
        if manualCollapse { return .compact }
        return (isHovered || isPinned) ? .expanded : .compact
    }

    var body: some View {
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                // ONE view for both phases — ExpandedView is told whether
                // to render the compact-bar form or the full panel via
                // `isExpanded`. Inside, its frame animates between the
                // two sizes and the section / hairline / footer content
                // appears or disappears with their own transitions.
                // No two stacked views, no fade-on-top — a single
                // morphing component.
                ExpandedView(
                    isExpanded: phase == .expanded,
                    isPinned: $isPinned,
                    onCollapse: collapse,
                    onSizeChange: { size in
                        if phase == .expanded {
                            expandedSize = size
                        } else {
                            compactSize = size
                        }
                        onSizeChange(size)
                    }
                )
                // Strictly shape-bounded hit area — hover fires only
                // when the cursor is over the actual visible black
                // surface, never the transparent corner pixels of the
                // bounding rect.
                .contentShape(currentHitShape)
                .onHover { hovering in
                    // While a menu is open the cursor is over the menu
                    // popup, not the panel — ignore the spurious
                    // hover-out so the panel stays put.
                    guard !isMenuOpen else { return }
                    isHovered = hovering
                    if !hovering { manualCollapse = false }
                }
                Spacer()
            }
            // No top padding — the panel extends UP into the notch zone.
            Spacer()
        }
        // Hover expand/collapse snaps instantly — no spring morph. The
        // bouncy `Theme.Animations.notch` overshoot read as an unwanted
        // up-and-down motion on hover, so the phase change is unanimated.
        .animation(nil, value: phase)
        .onChange(of: phase) { _, newValue in
            onSizeChange(currentSize(for: newValue))
        }
        .onAppear {
            onSizeChange(currentSize(for: phase))
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentTabRequestCollapse)) { _ in
            collapse()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            scheduleMenuClose()
        }
        // Custom in-app overlays (the per-row priority picker popover)
        // get the exact same treatment as NSMenu tracking.
        .onReceive(NotificationCenter.default.publisher(for: .agentTabOverlayOpen)) { _ in
            isMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentTabOverlayClosed)) { _ in
            scheduleMenuClose()
        }
    }

    /// Clear `isMenuOpen` after a beat: when a menu / popover closes the
    /// cursor is often still off-panel for an instant, which would fire
    /// a trailing `.onHover(false)`. Holding the flag briefly lets that
    /// settle before normal hover tracking resumes.
    private func scheduleMenuClose() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            self.isMenuOpen = false
        }
    }

    private func collapse() {
        isPinned = false
        isHovered = false
        // Suppress re-expansion until the cursor leaves the compact area
        // — fixes the "click chevron, panel collapses then immediately
        // re-opens because cursor is still over the compact surface".
        // Auto-clear after a short window so the flag never gets stuck
        // (e.g. when the cursor exited via a region SwiftUI's onHover
        // didn't fire on, leaving manualCollapse true and blocking the
        // next hover-to-expand).
        manualCollapse = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.manualCollapse = false
        }
    }

    private func currentSize(for phase: Phase) -> CGSize {
        switch phase {
        case .compact:  return compactSize
        case .expanded: return expandedSize
        }
    }

    /// Hit-test shape — same shape for both phases since the unified
    /// view uses one shape that just resizes.
    private var currentHitShape: AnyShape {
        AnyShape(CompactBarShape(topRadius: 6, bottomRadius: 10))
    }
}

extension Notification.Name {
    /// Posted by NotchPanel when the user clicks outside the live region or
    /// presses Esc while the panel is up.
    static let agentTabRequestCollapse = Notification.Name("AgentTAB.RequestCollapse")

    /// Posted when something (typically a toast tap) wants the
    /// auto-hidden notch to briefly slide down so the user sees
    /// what they're being navigated to.
    static let agentTabRequestPeek = Notification.Name("AgentTAB.RequestPeek")

    /// Posted by a custom in-app overlay (the per-row priority picker
    /// popover) when it opens / closes. The panel and NotchView treat
    /// these like NSMenu tracking — keep the panel expanded and
    /// interactive while the overlay is up.
    static let agentTabOverlayOpen   = Notification.Name("AgentTAB.OverlayOpen")
    static let agentTabOverlayClosed = Notification.Name("AgentTAB.OverlayClosed")
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
