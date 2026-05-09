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

struct ExpandedView: View {
    @EnvironmentObject var engine: ActivityEngine
    @Environment(\.notchGeometry) var geometry

    @Binding var isPinned: Bool
    var onCollapse: () -> Void = {}

    /// Reports the rendered size up to NotchView so the host NSPanel can
    /// size its click-through region to exactly the visible black surface.
    var onSizeChange: (CGSize) -> Void = { _ in }

    @State private var isOlderOpen: Bool = false   // closed by default — content-sized
    @State private var showSettings: Bool = false
    @State private var isEditMode: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Pitch-black panel — extends UP into the notch zone so the panel
            // and the hardware notch read as one continuous shape. The shape
            // sizes to the VStack below it via `.background`.
            VStack(spacing: 12) {
                // 12pt below the menu bar so the hairline is fully visible
                // end-to-end rather than tucked against the notch's bottom edge.
                statusHairline
                    .padding(.horizontal, Theme.Layout.statusHairlineInset)
                    .padding(.top, 12)

                header
                if showSettings {
                    SettingsBody()
                        .transition(.opacity)
                } else {
                    sections
                        .transition(.opacity)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, geometry.notchHeight)
            .frame(width: Theme.Layout.expandedWidth, alignment: .top)
            .background(
                DropPanelShape(cornerRadius: Theme.Layout.expandedCornerRadius)
                    .fill(Color.black)
            )
            .clipShape(DropPanelShape(cornerRadius: Theme.Layout.expandedCornerRadius))
            // Soft drop shadow — small core, blurry halo. The two layers
            // give the falloff that radius alone can't (one shadow keeps a
            // hard ring; two stacked produce a feathered edge).
            .shadow(color: .black.opacity(0.55), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.30), radius: 32, x: 0, y: 18)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: ExpandedSizeKey.self, value: g.size)
                }
            )
        }
        .animation(Theme.Animations.notch, value: isOlderOpen)
        .animation(Theme.Animations.notch, value: showSettings)
        .onPreferenceChange(ExpandedSizeKey.self) { size in
            onSizeChange(size)
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

    private var header: some View {
        HStack(spacing: 12) {
            modeBox
            TaskChip(id: headerChipId, accent: .blue, size: .sm)

            VStack(alignment: .leading, spacing: 1) {
                Text("AgentTab")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textStrong)
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                    Text(shellLabel)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                if attentionCount > 0 { CountBadge(kind: .amber, count: attentionCount) }
                if inProgressCount > 0 { CountBadge(kind: .blue, count: inProgressCount) }
                CountBadge(kind: .green, count: doneCount)
            }
        }
    }

    private var modeBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )

            Group {
                switch mode {
                case .attention: AttnGlyph(size: 16)
                case .active:    RotatingLoader(size: 16, color: Theme.Neon.blue)
                case .idle:      CoffeeIdle(size: 16)
                }
            }
        }
        .frame(width: 32, height: 32)
    }

    private var headerChipId: String {
        if let s = topActiveSession {
            switch s.terminalKind {
            case .zellij(let info): return "\(info.tabIndex)"
            case .generic:          return String(s.claudeSessionId.suffix(2))
            }
        }
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
        VStack(spacing: 12) {
            if !activeSessions.isEmpty {
                Section(label: "ACTIVE") {
                    grid(of: activeSessions, variant: .active)
                }
            }
            if !attentionSessions.isEmpty {
                Section(label: "NEEDS ATTENTION", tint: .amber) {
                    grid(of: attentionSessions, variant: .attention)
                }
            }
            if !restingSessions.isEmpty {
                Section(
                    label: "OLDER · \(restingSessions.count)",
                    tint: .dim,
                    collapsible: true,
                    isOpen: $isOlderOpen
                ) {
                    if isOlderOpen {
                        // Cap the older grid height so a long list scrolls
                        // rather than blowing the panel up. When closed the
                        // section contributes zero height and the panel
                        // collapses to header + active + footer.
                        ScrollView(showsIndicators: false) {
                            grid(of: restingSessions) { variantForOlder($0) }
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }
            if activeSessions.isEmpty && attentionSessions.isEmpty && restingSessions.isEmpty {
                emptyState
            }
        }
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

    private func grid(of sessions: [Session], variant: AgentRow.Variant) -> some View {
        grid(of: sessions) { _ in variant }
    }

    private func grid(
        of sessions: [Session],
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
                    onUnlink: { /* hooked up in M5 denylist */ }
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
                    showSettings.toggle()
                }
                FootBtn(systemImage: "pencil", isOn: isEditMode) {
                    isEditMode.toggle()
                }
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

    // MARK: - Derivations

    private enum Mode { case idle, active, attention }

    private var mode: Mode {
        if attentionCount > 0 { return .attention }
        if inProgressCount > 0 { return .active }
        return .idle
    }

    private var inProgressCount: Int { activeSessions.count }
    private var attentionCount: Int { attentionSessions.count }
    /// Green counter — only sessions that completed during this AgentTAB
    /// run. Historical jsonl files surfaced as `.done` for the OLDER list
    /// are excluded; otherwise every stale transcript would inflate the
    /// counter even though nothing happened this run.
    private var doneCount: Int {
        engine.displaySessions.filter {
            $0.activity == .done && !$0.isHistorical
        }.count
    }

    private var activeSessions: [Session] {
        engine.displaySessions.filter {
            switch $0.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }
    }

    private var attentionSessions: [Session] {
        engine.displaySessions.filter { $0.activity == .waiting }
    }

    private var restingSessions: [Session] {
        engine.displaySessions.filter {
            switch $0.activity {
            case .done, .idle, .initState: return true
            default: return false
            }
        }.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private var topActiveSession: Session? {
        activeSessions.first ?? attentionSessions.first ?? restingSessions.first
    }

    private func handleClick(_ session: Session) {
        switch session.terminalKind {
        case .zellij(let info):
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["zellij", "action", "focus-pane", "\(info.paneId)"]
            try? task.run()
        case .generic:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.projectPath)])
        }
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
