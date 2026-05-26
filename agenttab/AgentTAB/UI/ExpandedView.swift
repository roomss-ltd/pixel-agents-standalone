// ExpandedView.swift — fully pinned 720×460 panel.
//
// Mirrors `notch.jsx:ExpandedPanel` faithfully:
//   * pitch-black DropPanelShape, 22pt bottom corners
//   * 1.2pt status hairline at top, glow tinted by mode
//   * header grid: mode-glyph box | header chip | title + shell | counts
//   * sections: ACTIVE (top), NEEDS ATTENTION (amber-tinted), OLDER (collapsible)
//   * footer: gear + pencil on the left, pin + collapse on the right
//   * empty state: "All agents resting"

import AppKit
import SwiftUI

private struct ExpandedSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct LeftIntrinsicKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct RightIntrinsicKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ExpandedView: View {
    @EnvironmentObject var engine: ActivityEngine
    @EnvironmentObject var tokenTracker: TokenTracker
    @Environment(\.notchGeometry) var geometry

    /// `false` renders the compact-bar form (just the header sized to a
    /// notch-bar). `true` renders the full panel. Both forms share the
    /// same single SwiftUI view tree so the transition animates a frame
    /// resize + content reveal — no separate views to cross-fade.
    let isExpanded: Bool
    @Binding var isPinned: Bool
    var onCollapse: () -> Void = {}

    /// Reports the rendered size up to NotchView so the host NSPanel can
    /// size its click-through region to exactly the visible black surface.
    var onSizeChange: (CGSize) -> Void = { _ in }

    @State private var isOlderOpen: Bool = false   // closed by default — content-sized
    @State private var showSettings: Bool = false
    @State private var showHistory: Bool = false   // activity dashboard (7d / 30d / squares)
    @State private var isEditMode: Bool = false

    /// Section ordering mode. `.recency` keeps the original behaviour
    /// (tab-index for live sections, last-update for finished ones);
    /// `.priority` sorts by the user-assigned Priority first, then
    /// falls back to the same secondary key. Persisted so it sticks
    /// across launches.
    enum SortMode: String, CaseIterable { case recency, priority }
    @AppStorage("AgentTAB.sortMode") private var sortModeRaw: String = SortMode.recency.rawValue
    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .recency }

    /// Bumped on every expand. Passed down to each AgentRow so its
    /// staggered pop-in re-runs reliably even when LazyVGrid reuses the
    /// row view (which keeps the row's `@State` alive).
    @State private var expandGeneration: Int = 0

    /// Same idea, scoped to the collapsible OLDER FINISHED section —
    /// bumped when that section is opened so its rows stagger in on
    /// open, exactly the way the always-visible sections stagger on
    /// panel expand. Without a separate counter the OLDER rows would
    /// either never stagger or re-stagger the whole panel.
    @State private var olderGeneration: Int = 0

    /// Compact-form bar width. ~42pt wings host a single SLIM icon
    /// centred per side with explicit outer-edge padding so the icon
    /// sits clearly inside its allocated square (not flush against
    /// the bar's rounded corner). Middle 220pt covers the hardware
    /// notch.
    private static let compactBarWidth: CGFloat = 304

    var body: some View {
        let edgeInset: CGFloat = isExpanded ? 10 : 6
        let notchSpan: CGFloat = isExpanded
            ? max(geometry.notchWidth, 230)
            : max(geometry.notchWidth, 220)
        let panelWidth: CGFloat = isExpanded
            ? Theme.Layout.expandedWidth
            : Self.compactBarWidth

        VStack(spacing: 0) {
            // Header — always present, lives in the notch zone.
            notchLevelHeader(edgeInset: edgeInset, notchSpan: notchSpan)
                .frame(height: geometry.hasNotch ? geometry.notchHeight : Theme.Layout.compactHeight)

            // Below the notch — only when expanded. Has its own
            // .transition so the inner content fades / slides as the
            // outer frame grows / shrinks.
            if isExpanded {
                statusHairline
                    .padding(.horizontal, Theme.Layout.statusHairlineInset)
                    .padding(.top, 4)

                VStack(spacing: 12) {
                    if showSettings {
                        SettingsBody()
                            .transition(.opacity)
                    } else if showHistory {
                        ActivityHistoryView(
                            tracker: tokenTracker,
                            onBack: { showHistory = false }
                        )
                        .transition(.opacity)
                    } else {
                        sections
                            .transition(.opacity)
                    }
                    footer
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: panelWidth, alignment: .top)
        .background(
            // Single shape for both phases — the bar morphs in size,
            // not in shape. Compact-bar's outward-flaring top corners
            // are subtle enough (6pt) to read fine at expanded scale.
            CompactBarShape(topRadius: 6, bottomRadius: 10)
                .fill(Color.black)
        )
        .clipShape(CompactBarShape(topRadius: 6, bottomRadius: 10))
        .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: ExpandedSizeKey.self, value: g.size)
            }
        )
        .animation(Theme.Animations.notch, value: isExpanded)
        .animation(Theme.Animations.notch, value: isOlderOpen)
        .animation(Theme.Animations.notch, value: showSettings)
        .animation(Theme.Animations.notch, value: showHistory)
        .onPreferenceChange(ExpandedSizeKey.self) { size in
            onSizeChange(size)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                expandGeneration &+= 1
                tokenTracker.refresh()
            }
        }
        .onChange(of: isOlderOpen) { _, open in
            if open { olderGeneration &+= 1 }
        }
    }

    // MARK: - Status hairline

    private var statusHairline: some View {
        Rectangle()
            .fill(hairlineColor)
            .frame(height: Theme.Layout.statusHairlineHeight)
            .opacity(hairlineColor == .clear ? 0 : 0.9)
            .shadow(color: hairlineColor, radius: 4)
            .clipShape(Capsule())
    }

    /// Hairline color follows the user's spec:
    ///   * amber → at least one agent needs attention
    ///   * blue  → at least one agent is actively processing
    ///   * green → no active or attention work, but finished work exists
    ///   * clear → no sessions at all
    private var hairlineColor: Color {
        if attentionCount > 0 { return Theme.Neon.amber }
        if inProgressCount > 0 { return Theme.Neon.blue }
        if !engine.displaySessions.isEmpty { return Theme.Neon.green }
        return .clear
    }

    // MARK: - Header

    /// Header at notch level. Compact and expanded forms share the
    /// outer HStack, but the wing content differs:
    ///   * compact  → single alternating counter centred on the left,
    ///               glyph centred on the right (symmetric wings).
    ///   * expanded → counters flushed against the notch's left edge,
    ///               glyph flushed against its right edge (current
    ///               expanded-panel layout untouched).
    private func notchLevelHeader(edgeInset: CGFloat, notchSpan: CGFloat) -> some View {
        let counterScale: CGFloat = isExpanded ? 1.15 : 1.0
        let glyphSize: CGFloat = isExpanded ? 24 : 16

        return HStack(spacing: 0) {
            if isExpanded {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    counterCluster(scale: counterScale)
                        .padding(.trailing, edgeInset)
                }
            } else {
                // Compact: outer-edge padding pushes the counter off
                // the bar's rounded BL corner so it sits clearly inside
                // its allocated square instead of hugging the curve.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    compactAlternatingCounter
                        .padding(.leading, 8)
                    Spacer(minLength: 0)
                }
            }

            Color.clear.frame(width: notchSpan)

            if isExpanded {
                HStack(spacing: 0) {
                    glyphCluster(size: glyphSize)
                        .padding(.leading, edgeInset)
                    Spacer(minLength: 0)
                }
            } else {
                // Compact: outer-edge padding mirrors the counter's
                // — pushes the glyph off the bar's rounded BR corner.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    glyphCluster(size: glyphSize)
                        .padding(.trailing, 8)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Compact-mode-only counter.
    ///   * Both running and finished agents present → alternate every 4s.
    ///   * Nothing running (all agents finished) → green-only, no swap.
    ///   * Only running, nothing done → blue-only, no swap.
    private var compactAlternatingCounter: some View {
        Group {
            if inProgressCount == 0 {
                compactSlimBadge(color: Theme.Neon.green, count: doneCount)
            } else if doneCount == 0 {
                compactSlimBadge(color: Theme.Neon.blue, count: inProgressCount)
            } else {
                TimelineView(.periodic(from: .now, by: 4)) { context in
                    let phase = Int(context.date.timeIntervalSince1970 / 4) % 2
                    ZStack {
                        if phase == 0 {
                            compactSlimBadge(color: Theme.Neon.blue, count: inProgressCount)
                                .transition(.opacity)
                        } else {
                            compactSlimBadge(color: Theme.Neon.green, count: doneCount)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: phase)
                }
            }
        }
    }

    private func compactSlimBadge(color: Color, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.7), radius: 1.2)
            Text("\(count)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.36), lineWidth: 0.5))
    }

    private func counterCluster(scale: CGFloat) -> some View {
        HStack(spacing: 6) {
            if attentionCount > 0 { CountBadge(kind: .amber, count: attentionCount) }
            // Expanded view shows BOTH counters at all times so the user
            // can see active + done states side by side; compact mode
            // alternates between them via `compactAlternatingCounter`.
            CountBadge(kind: .blue, count: inProgressCount)
            CountBadge(kind: .green, count: doneCount)
        }
        .scaleEffect(scale)
    }

    @ViewBuilder
    private func glyphCluster(size: CGFloat) -> some View {
        switch mode {
        case .attention: AttnGlyph(size: size)
        case .active:    RotatingLoader(size: size, color: Theme.Neon.blue)
        case .idle:      CoffeeIdle(size: size)
        }
    }

    private var headerChipId: String {
        if let s = topActiveSession { return engine.displayLabel(for: s) }
        return "—"
    }

    private var shellLabel: String {
        if engine.displaySessions.contains(where: { if case .zellij = $0.terminalKind { return true } else { return false } }) {
            return "zellij · agents"
        }
        return "Bash"
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        let hasAny = !activeSessions.isEmpty || !attentionSessions.isEmpty
            || !recentlyActiveSessions.isEmpty || !olderFinishedSessions.isEmpty

        VStack(spacing: 12) {
            // Header row — daily token spend on the left, the
            // recency/priority sort switcher on the right. Only shown
            // when there's at least one session to look at.
            if hasAny {
                HStack {
                    tokenCounter
                    Spacer()
                    sortModeToggle
                }
            }
            if !activeSessions.isEmpty {
                Section(label: "ACTIVE") {
                    grid(of: activeSessions, variant: .active, generation: expandGeneration)
                }
            }
            if !attentionSessions.isEmpty {
                Section(label: "NEEDS ATTENTION", tint: .amber) {
                    grid(of: attentionSessions, variant: .attention, generation: expandGeneration)
                }
            }
            // Recently active — finished within the last hour. Mirrors
            // Hammerspoon's `RECENTLY ACTIVE` row group: green tinted,
            // always visible (not collapsed).
            if !recentlyActiveSessions.isEmpty {
                Section(label: "RECENTLY ACTIVE") {
                    grid(of: recentlyActiveSessions, variant: .finished, generation: expandGeneration)
                }
            }
            // Older finished — beyond an hour, or idle/init. Collapsible
            // so the panel stays compact when there's a long history.
            // Uses `olderGeneration` so its rows stagger in when the
            // section is opened — the same effect the always-visible
            // sections get on panel expand.
            if !olderFinishedSessions.isEmpty {
                Section(
                    label: "OLDER FINISHED · \(olderFinishedSessions.count)",
                    tint: .dim,
                    collapsible: true,
                    isOpen: $isOlderOpen
                ) {
                    if isOlderOpen {
                        ScrollView(showsIndicators: false) {
                            grid(of: olderFinishedSessions, generation: olderGeneration) {
                                variantForOlder($0)
                            }
                        }
                        .frame(maxHeight: Theme.Layout.cardHeight * 3 + 12)
                    }
                }
            }
            if activeSessions.isEmpty && attentionSessions.isEmpty
                && recentlyActiveSessions.isEmpty && olderFinishedSessions.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Token counter

    /// Daily token-spend pill — total tokens across every agent that
    /// ran on this machine today. Sits at the top-left of the sections,
    /// mirroring the sort switcher on the right. Resets at midnight
    /// (handled inside TokenTracker). Tapping it flips the panel to the
    /// activity dashboard (7d / 30d / squares).
    private var tokenCounter: some View {
        Button {
            showSettings = false
            tokenTracker.refreshHistory()
            withAnimation(Theme.Animations.notch) { showHistory = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.Neon.blue)
                Text(TokenTracker.format(tokenTracker.todayTokens))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textStrong)
                Text("tokens today")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Tokens spent across all agents today — tap for the activity history")
    }

    // MARK: - Sort-mode toggle

    /// Visible two-segment switcher: Recency ⇄ Priority. Sits at the
    /// top-right of the sections so the current ordering mode is
    /// always obvious — not buried as a footer icon.
    private var sortModeToggle: some View {
        HStack(spacing: 2) {
            sortSegment(.recency, label: "Recency", icon: "clock")
            sortSegment(.priority, label: "Priority", icon: "flag.fill")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        )
    }

    private func sortSegment(_ mode: SortMode, label: String, icon: String) -> some View {
        let selected = sortMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                sortModeRaw = mode.rawValue
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.textStrong : Theme.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.Neon.blueSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Theme.Neon.blueEdge : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            CoffeeIdle(size: 36)
            Text("All agents resting")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func grid(
        of sessions: [Session],
        variant: AgentRow.Variant,
        generation: Int
    ) -> some View {
        grid(of: sessions, generation: generation) { _ in variant }
    }

    private func grid(
        of sessions: [Session],
        generation: Int,
        variant: @escaping (Session) -> AgentRow.Variant
    ) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(sessions) { session in
                AgentRow(
                    session: session,
                    variant: variant(session),
                    isEdit: isEditMode,
                    onClick: { handleClick(session) },
                    onUnlink: { engine.hide(session) },
                    onOpenFolder: { engine.openFolder(session) },
                    onOpenEditor: { engine.openEditor(session) },
                    onSetPriority: { engine.setPriority($0, for: session) },
                    appearanceGeneration: generation
                )
            }
        }
    }

    /// In the OLDER section, sessions that completed with `.done` get the
    /// green "finished" tint; idle/init sessions stay neutral.
    private func variantForOlder(_ session: Session) -> AgentRow.Variant {
        switch session.activity {
        case .done:                return .finished
        case .idle, .initState:    return .resting
        default:                   return .resting
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                FootBtn(systemImage: "gearshape", isOn: showSettings) {
                    showHistory = false
                    showSettings.toggle()
                }
                FootBtn(systemImage: "pencil", isOn: isEditMode) {
                    isEditMode.toggle()
                }
                appMenuButton
            }
            Spacer()
            HStack(spacing: 6) {
                FootBtn(systemImage: isPinned ? "pin.fill" : "pin", isOn: isPinned) {
                    isPinned.toggle()
                }
                FootBtn(systemImage: "chevron.up", isOn: false) {
                    onCollapse()
                }
            }
        }
    }

    /// Footer "⋯" menu — quick access to app-level actions
    /// (quit, uninstall, about).
    private var appMenuButton: some View {
        Menu {
            Button("About AgentTAB") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Uninstall…") { promptUninstall() }
            Divider()
            Button("Quit AgentTAB") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Confirm + run the uninstaller. Removes hook scripts, clears
    /// stored preferences, and quits — the user then drags
    /// AgentTAB.app to the Trash to complete the uninstall.
    private func promptUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall AgentTAB?"
        alert.informativeText = "Removes Claude Code hook scripts and stored preferences. After this, drag AgentTAB.app to the Trash to finish uninstalling."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Remove hook scripts if installed.
        if HookInstaller.hooksInstalled {
            try? HookInstaller.uninstall()
        }
        // Clear stored preferences for this bundle.
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        NSApp.terminate(nil)
    }

    // MARK: - Derivations

    private enum Mode { case idle, active, attention }

    private var mode: Mode {
        if attentionCount > 0 { return .attention }
        if inProgressCount > 0 { return .active }
        return .idle
    }

    private var inProgressCount: Int { activeSessions.count }
    private var attentionCount: Int { attentionSessions.count }
    /// Green counter — uses the engine's single source of truth so
    /// compact and expanded views can never diverge.
    private var doneCount: Int { engine.recentlyActiveDoneSessions().count }

    /// Apply the active SortMode. In `.recency` the caller's
    /// `secondary` comparator is the whole ordering (original
    /// behaviour). In `.priority` we sort by Priority descending
    /// first, then fall back to `secondary` within each level.
    private func sortedByMode(
        _ list: [Session],
        secondary: @escaping (Session, Session) -> Bool
    ) -> [Session] {
        switch sortMode {
        case .recency:
            return list.sorted(by: secondary)
        case .priority:
            return list.sorted { a, b in
                if a.priority != b.priority {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return secondary(a, b)
            }
        }
    }

    private var activeSessions: [Session] {
        let filtered = engine.displaySessions.filter {
            switch $0.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }
        return sortedByMode(filtered, secondary: ActivityEngine.byTabIndexAsc)
    }

    private var attentionSessions: [Session] {
        let filtered = engine.displaySessions.filter { $0.activity == .waiting }
        return sortedByMode(filtered, secondary: ActivityEngine.byTabIndexAsc)
    }

    /// Cutoff for the recently-active vs. older split. Lives on
    /// `ActivityEngine` so the compact notch's green badge uses the
    /// same threshold as this view.
    private static var recentFinishedWindow: TimeInterval { ActivityEngine.recentFinishedWindow }

    private var restingSessions: [Session] {
        let filtered = engine.displaySessions.filter {
            switch $0.activity {
            case .done, .idle, .initState: return true
            default: return false
            }
        }
        return sortedByMode(filtered, secondary: { $0.lastUpdate > $1.lastUpdate })
    }

    /// RECENTLY ACTIVE = only `.done` within the window (or any
    /// `.urgent` session, which never ages out — see
    /// `engine.recentlyActiveDoneSessions()`).
    private var recentlyActiveSessions: [Session] {
        sortedByMode(engine.recentlyActiveDoneSessions(),
                     secondary: { $0.lastUpdate > $1.lastUpdate })
    }

    /// OLDER FINISHED = any `.done` or `.idle` session past the
    /// recently-active window, plus `.initState` (starting-but-stalled).
    /// `.urgent` sessions are explicitly excluded — they stay in
    /// RECENTLY ACTIVE forever, mirroring the engine's predicate.
    private var olderFinishedSessions: [Session] {
        let now = Date()
        let filtered = engine.displaySessions.filter { s in
            // Urgent never goes to OLDER, regardless of elapsed time.
            if s.priority == .urgent { return false }
            switch s.activity {
            case .done, .idle:
                return now.timeIntervalSince(s.lastUpdate) > Self.recentFinishedWindow
            case .initState:
                return true
            default:
                return false
            }
        }
        return sortedByMode(filtered, secondary: { $0.lastUpdate > $1.lastUpdate })
    }

    private var topActiveSession: Session? {
        activeSessions.first ?? attentionSessions.first ?? restingSessions.first
    }

    private func handleClick(_ session: Session) {
        engine.focus(session)
    }
}

// MARK: - Section header (dashed-line border + label, optional collapse)

private struct Section<Content: View>: View {
    let label: String
    var tint: SectionTint = .normal
    var collapsible: Bool = false
    var isOpen: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content

    enum SectionTint { case normal, amber, dim }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            dash
            HStack(spacing: 6) {
                if collapsible, let isOpen {
                    Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(Theme.Layout.sectionLabelLetterSpacing)
            }
            .foregroundStyle(labelColor)
            dash
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsible, let isOpen {
                withAnimation(.easeOut(duration: 0.18)) {
                    isOpen.wrappedValue.toggle()
                }
            }
        }
    }

    private var labelColor: Color {
        switch tint {
        case .amber:  return Theme.Neon.amber
        case .dim:    return Theme.textFaint
        case .normal: return Theme.textDim
        }
    }

    private var dash: some View {
        Rectangle()
            .fill(dashColor)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    private var dashColor: Color {
        switch tint {
        case .amber: return Theme.Neon.amber.opacity(0.24)
        default:     return Theme.hairline
        }
    }
}

// MARK: - Footer button

private struct FootBtn: View {
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Theme.Neon.blue : Theme.textDim)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Theme.Neon.blueSoft : Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isOn ? Theme.Neon.blueEdge : Theme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings body

private struct SettingsBody: View {
    @State private var sounds = true
    @State private var waitingReminders = true
    @State private var waitingPulse = true
    @State private var notifications = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Options")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textStrong)
                .padding(.bottom, 4)

            row(label: "Sounds", isOn: $sounds)
            row(label: "Waiting reminders", isOn: $waitingReminders)
            row(label: "Waiting pulse", isOn: $waitingPulse)
            row(label: "Show notifications", isOn: $notifications)
        }
    }

    private func row(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textStrong)
            Spacer()
            NeonToggle(isOn: isOn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        )
    }
}

private struct NeonToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Neon.blue : Color.white.opacity(0.16))
                    .frame(width: 34, height: 20)
                    .shadow(color: isOn ? Theme.Neon.blueEdge : .clear, radius: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
            }
            .frame(width: 34, height: 20)
        }
        .buttonStyle(.plain)
    }
}
