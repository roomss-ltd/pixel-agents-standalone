// AgentRow.swift — compact AgentTab card. Designed for a 3-column grid in
// the expanded panel. Replaces the prior dense SessionRow.
//
// Mirrors `notch.jsx:AgentTab` exactly:
//   * 6×7 padding, 8pt corner radius
//   * 7pt internal column gap
//   * left: xs TaskChip
//   * middle: name (11.5/600) + monospace activity (9.5/faint)
//   * right: status icon (loader / warn / claude / unlink)
//   * variants: active / attention / finished (resting) / edit-mode

import AppKit
import SwiftUI

struct AgentRow: View {
    let session: Session
    var variant: Variant = .resting
    var isEdit: Bool = false
    var onClick: () -> Void = {}
    var onUnlink: () -> Void = {}
    var onOpenFolder: () -> Void = {}
    var onOpenEditor: () -> Void = {}
    var onSetPriority: (Priority) -> Void = { _ in }
    /// Bumped by ExpandedView on every expand. AgentRow watches it so
    /// the staggered pop-in re-runs each time the notch opens — even
    /// when LazyVGrid reuses the same row view instance (which keeps
    /// `@State` alive and would otherwise make the effect fire once).
    var appearanceGeneration: Int = 0

    enum Variant { case active, attention, finished, resting }

    @EnvironmentObject var engine: ActivityEngine
    @State private var isHovered = false
    @State private var showPriorityPicker = false
    /// Drives the staggered "pop-in" when the panel expands. Each row
    /// starts hidden and reveals itself after its own random delay, so
    /// the grid fills in one tab at a time in a random order rather
    /// than every tab fading in together. `@State` resets to false
    /// each time the row re-enters the hierarchy (i.e. every expand).
    @State private var hasAppeared = false

    /// Show the hover action cluster whenever the cursor is over the
    /// row and edit mode is off. Buttons are visually dimmed (and
    /// no-op with a log line) when there's no resolvable path, so the
    /// affordance is always discoverable even for Zellij-only sessions
    /// that were never matched to a JSONL file.
    private var showsHoverActions: Bool {
        isHovered && !isEdit
    }

    private var hasWorktreePath: Bool {
        engine.worktreePath(for: session) != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            priorityMenu

            TaskChip(
                id: chipId,
                accent: chipAccent,
                size: .xs,
                muted: variant == .resting
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(engine.displayName(for: session))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(activityText)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(activityColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right slot — fixed 44pt so the row layout doesn't shift
            // when hover swaps the contents.
            ZStack(alignment: .trailing) {
                if showsHoverActions {
                    hoverActions
                        .transition(.opacity)
                } else {
                    statusIcon
                        .frame(width: 20, height: 20)
                        .transition(.opacity)
                }
            }
            .frame(width: 44, height: 20, alignment: .trailing)
            .animation(.easeOut(duration: 0.12), value: showsHoverActions)
        }
        .padding(.horizontal, Theme.Layout.cardPaddingH)
        .padding(.vertical, Theme.Layout.cardPaddingV)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        // Staggered random pop-in: hidden until the row's own delay
        // elapses, then springs to full size + opacity.
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.82)
        // `.identity` so an ambient `.animation(_:value:)` scope (the
        // panel's isExpanded / isOlderOpen scopes) never layers a
        // default fade-in on top of `staggerIn()`. Every row in every
        // section then has exactly one appearance animation: the
        // spring stagger.
        .transition(.identity)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
            if hovering {
                AgentLog.panel.debug("row hover session=\(session.claudeSessionId, privacy: .public) hasPath=\(hasWorktreePath)")
            }
        }
        .onTapGesture {
            if isEdit {
                onUnlink()
            } else {
                onClick()
            }
        }
        .onAppear { staggerIn() }
        .onChange(of: appearanceGeneration) { _, _ in staggerIn() }
    }

    /// Hide instantly, then spring back in after a random 0–0.4s delay.
    /// The hide is committed on this runloop tick and the animated
    /// reveal is deferred to the next, so SwiftUI can't coalesce them
    /// into a no-op (which would skip the effect on re-expand).
    private func staggerIn() {
        hasAppeared = false
        DispatchQueue.main.async {
            let delay = Double.random(in: 0 ... 0.4)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72).delay(delay)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Priority dropdown

    /// Bare icon in the priority's neon colour (no box, no glow).
    private var priorityChip: some View {
        Image(systemName: session.priority.systemImage)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(session.priority.color)
            .frame(width: 17, height: 17)
    }

    /// The chip is a plain `Button` that opens a CUSTOM popover — not
    /// an `NSMenu` — so the dropdown can be fully styled to the
    /// neon-dark theme with colour-coded icons. The popover lives in
    /// its own window outside the panel, so it posts
    /// `.agentTabOverlayOpen` / `.agentTabOverlayClosed` to keep the
    /// notch from collapsing while it's up (same guard NSMenus get).
    private var priorityMenu: some View {
        Button {
            showPriorityPicker.toggle()
        } label: {
            priorityChip
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Priority — \(session.priority.displayName)")
        .popover(isPresented: $showPriorityPicker, arrowEdge: .bottom) {
            PriorityPickerView(current: session.priority) { level in
                onSetPriority(level)
                showPriorityPicker = false
            }
        }
        .onChange(of: showPriorityPicker) { _, open in
            NotificationCenter.default.post(
                name: open ? .agentTabOverlayOpen : .agentTabOverlayClosed,
                object: nil
            )
        }
    }

    // MARK: - Hover actions

    /// Two icon buttons revealed on hover. Each button consumes its own
    /// tap (Button(.plain) is sufficient to prevent the gesture from
    /// bubbling to the row's onTapGesture), so the body-tap → terminal
    /// behaviour is preserved everywhere outside these glyphs.
    private var hoverActions: some View {
        let pathTip = hasWorktreePath ? "" : " (no path resolved)"
        return HStack(spacing: 4) {
            actionButton(
                systemName: "folder.fill",
                tooltip: "Reveal in Finder" + pathTip,
                action: onOpenFolder
            )
            actionButton(
                systemName: "chevron.left.forwardslash.chevron.right",
                tooltip: "Open in Cursor / VS Code" + pathTip,
                action: onOpenEditor
            )
        }
        .opacity(hasWorktreePath ? 1.0 : 0.45)
    }

    /// SwiftUI `Button` inside a nonactivating `NSPanel` sometimes fails
     /// to fire its action — the panel never becomes key, so the
     /// button's internal recognizer can swallow the press without
     /// calling through. A `highPriorityGesture(TapGesture())` on a
     /// styled `Image` is reliable in this context: it captures the
     /// tap before the row's `.onTapGesture` bubbles, and it doesn't
     /// require the host window to be key.
    private func actionButton(
        systemName: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .foregroundStyle(Theme.textStrong.opacity(0.85))
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .help(tooltip)
            .highPriorityGesture(
                TapGesture().onEnded {
                    AgentLog.panel.info("row action tap glyph=\(systemName, privacy: .public)")
                    action()
                }
            )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        if isEdit {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 0.5)
                    )
                UnlinkGlyph()
                    .stroke(
                        Theme.textDim,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 11, height: 11)
            }
        } else if variant == .attention {
            WarnGlyph()
                .stroke(
                    Theme.Neon.amber,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 11, height: 11)
        } else if variant == .active {
            CardioLoader(color: Theme.Neon.blue, size: 14)
        } else if variant == .finished {
            CheckGlyph()
                .stroke(
                    Theme.Neon.green,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 11, height: 11)
        } else {
            ClaudeGlyph()
                .stroke(
                    Theme.textFaint.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 11, height: 11)
        }
    }

    // MARK: - Tinting + colors

    private var backgroundColor: Color {
        switch variant {
        case .active:    return Theme.RowTint.activeBg
        case .attention: return Theme.RowTint.attentionBg
        case .finished:  return Theme.RowTint.finishedBg
        case .resting:   return isHovered ? Theme.RowTint.restingHover : Theme.RowTint.restingBg
        }
    }

    private var borderColor: Color {
        switch variant {
        case .active:    return Theme.RowTint.activeBorder
        case .attention: return Theme.RowTint.attentionBorder
        case .finished:  return Theme.RowTint.finishedBorder
        case .resting:   return Theme.RowTint.restingBorder
        }
    }

    private var textColor: Color {
        switch variant {
        case .resting:  return Theme.textStrong.opacity(0.65)
        case .finished: return Theme.textStrong.opacity(0.85)
        default:        return Theme.textStrong
        }
    }

    private var activityColor: Color {
        switch variant {
        case .attention: return Theme.Neon.amber
        default:         return Theme.textFaint
        }
    }

    private var chipAccent: TaskChip.Accent {
        switch variant {
        case .active:    return .blue
        case .attention: return .amber
        case .finished:  return .green
        case .resting:   return .green
        }
    }

    private var chipId: String { engine.displayLabel(for: session) }

    private var activityText: String {
        if let tool = session.currentTool, !tool.isEmpty {
            return tool
        }
        switch session.activity {
        case .thinking:    return "thinking"
        case .tool(let n): return n
        case .waiting:     return "awaiting approval"
        case .done:        return relativeTime(session.lastUpdate)
        case .initState:   return "starting"
        case .idle:        return relativeTime(session.lastUpdate)
        }
    }

    /// Compact relative-time formatting that mirrors the Hammerspoon
    /// webview: `5s`, `44m ago`, `169h ago`.
    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    }
}

// MARK: - Priority picker popover

/// Styled dark dropdown for the per-row priority picker. Each row is
/// the level's neon-coloured icon + name; the current level is
/// highlighted and checkmarked. Replaces the native NSMenu so the
/// dropdown matches the app's pitch-black neon aesthetic.
private struct PriorityPickerView: View {
    let current: Priority
    let onPick: (Priority) -> Void

    var body: some View {
        VStack(spacing: 1) {
            // Urgent at the top, Sidequest at the bottom — matches the
            // row chip's hierarchy and Linear's ordering.
            ForEach(Priority.allCases.reversed(), id: \.self) { level in
                row(level)
            }
        }
        .padding(5)
        .frame(width: 168)
        .background(Color(red: 0x0E / 255.0, green: 0x0E / 255.0, blue: 0x10 / 255.0))
    }

    private func row(_ level: Priority) -> some View {
        let isCurrent = level == current
        return Button {
            onPick(level)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: level.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(level.color)
                    .frame(width: 16)
                Text(level.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textStrong)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glyph paths used by the row

/// `icons.jsx:38` — unlink (broken-chain).
struct UnlinkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16.0
        var p = Path()
        p.move(to: CGPoint(x: 9 * s, y: 4 * s))
        p.addLine(to: CGPoint(x: 10.6 * s, y: 2.4 * s))
        p.addCurve(
            to: CGPoint(x: 14.1 * s, y: 5.9 * s),
            control1: CGPoint(x: 12.2 * s, y: 0.8 * s),
            control2: CGPoint(x: 14.1 * s, y: 2.7 * s)
        )
        p.addLine(to: CGPoint(x: 12.5 * s, y: 7.5 * s))

        p.move(to: CGPoint(x: 7 * s, y: 12 * s))
        p.addLine(to: CGPoint(x: 5.4 * s, y: 13.6 * s))
        p.addCurve(
            to: CGPoint(x: 1.9 * s, y: 10.1 * s),
            control1: CGPoint(x: 3.8 * s, y: 15.2 * s),
            control2: CGPoint(x: 1.9 * s, y: 13.3 * s)
        )
        p.addLine(to: CGPoint(x: 3.5 * s, y: 8.5 * s))

        p.move(to: CGPoint(x: 2 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 14 * s, y: 14 * s))
        return p
    }
}

/// `icons.jsx:103` — generic stylised "C".
struct ClaudeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16.0
        var p = Path()
        p.addArc(
            center: CGPoint(x: 8 * s, y: 8 * s),
            radius: 6 * s,
            startAngle: .degrees(0),
            endAngle: .degrees(360),
            clockwise: false
        )

        p.move(to: CGPoint(x: 11 * s, y: 6.5 * s))
        p.addCurve(
            to: CGPoint(x: 8 * s, y: 5 * s),
            control1: CGPoint(x: 10.4 * s, y: 5.6 * s),
            control2: CGPoint(x: 9.3 * s, y: 5 * s)
        )
        p.addArc(
            center: CGPoint(x: 8 * s, y: 8 * s),
            radius: 3 * s,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        p.addCurve(
            to: CGPoint(x: 11 * s, y: 9.5 * s),
            control1: CGPoint(x: 9.3 * s, y: 11 * s),
            control2: CGPoint(x: 10.4 * s, y: 10.4 * s)
        )
        return p
    }
}
