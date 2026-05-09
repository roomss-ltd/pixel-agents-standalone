// HoverPreviewView.swift — slim mid-state shown while the user is hovering
// the notch but hasn't pinned the full panel yet.
//
// Mirrors `notch.jsx:HoverPreview`: 360×86 drop panel, top row mirrors the
// compact counts strip, bottom row shows the most-relevant agent with a
// "↗ click to pin" affordance.

import SwiftUI

struct HoverPreviewView: View {
    @EnvironmentObject var engine: ActivityEngine

    @Environment(\.notchGeometry) var geometry

    var body: some View {
        let totalHeight = geometry.notchHeight + Theme.Layout.hoverHeight

        ZStack(alignment: .top) {
            DropPanelShape(cornerRadius: Theme.Layout.hoverCornerRadius)
                .fill(Theme.panelBg)

            VStack(alignment: .leading, spacing: 0) {
                statusHairline
                    .padding(.horizontal, Theme.Layout.statusHairlineInset)

                VStack(alignment: .leading, spacing: 8) {
                    topRow
                    Divider().background(Theme.hairline)
                    bottomRow
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .frame(height: Theme.Layout.hoverHeight)
            .padding(.top, geometry.notchHeight)
        }
        .frame(width: Theme.Layout.hoverWidth, height: totalHeight)
        .clipShape(DropPanelShape(cornerRadius: Theme.Layout.hoverCornerRadius))
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 10)
    }

    // MARK: - Top row (compact counts strip)

    private var topRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if mode == .attention {
                        AttnGlyph(size: 18)
                    } else if mode == .active {
                        RotatingLoader(size: 18, color: Theme.Neon.blue)
                    } else {
                        CoffeeIdle(size: 18)
                    }
                }
                if inProgressCount > 0 {
                    CountBadge(kind: .blue, count: inProgressCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Circle()
                .fill(Color.black)
                .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                .frame(width: 8, height: 8)

            HStack(spacing: 6) {
                if attentionCount > 0 {
                    CountBadge(kind: .amber, count: attentionCount)
                }
                CountBadge(kind: .green, count: doneCount)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Bottom row (current agent peek)

    @ViewBuilder
    private var bottomRow: some View {
        if let session = topSession {
            HStack(alignment: .center, spacing: 10) {
                TaskChip(id: chipId(for: session), accent: chipAccent(for: session), size: .sm)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textStrong)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9))
                        Text(session.currentTool ?? activityLabel(session.activity))
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("↗ click to pin")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        } else {
            HStack {
                Text("No active sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("↗ click to pin")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }

    // MARK: - Status hairline (same as compact)

    private var statusHairline: some View {
        Rectangle()
            .fill(hairlineColor)
            .frame(height: Theme.Layout.statusHairlineHeight)
            .opacity(mode == .idle ? 0 : 0.85)
            .shadow(color: hairlineColor, radius: 3)
            .clipShape(Capsule())
    }

    private var hairlineColor: Color {
        switch mode {
        case .attention: return Theme.Neon.amber
        case .active:    return Theme.Neon.blue
        case .idle:      return .clear
        }
    }

    // MARK: - Derivations

    private enum Mode { case idle, active, attention }

    private var mode: Mode {
        if attentionCount > 0 { return .attention }
        if inProgressCount > 0 { return .active }
        return .idle
    }

    private var inProgressCount: Int {
        engine.displaySessions.filter {
            switch $0.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }.count
    }

    private var attentionCount: Int {
        engine.displaySessions.filter { $0.activity == .waiting }.count
    }

    private var doneCount: Int {
        engine.displaySessions.filter { $0.activity == .done && !$0.isHistorical }.count
    }

    /// Most relevant session to feature: waiting > thinking/tool > most-recent
    /// done > most-recent.
    private var topSession: Session? {
        let sorted = engine.displaySessions.sorted { lhs, rhs in
            if lhs.activity.rank != rhs.activity.rank {
                return lhs.activity.rank > rhs.activity.rank
            }
            return lhs.lastUpdate > rhs.lastUpdate
        }
        return sorted.first
    }

    private func chipId(for session: Session) -> String {
        switch session.terminalKind {
        case .zellij(let info): return "\(info.tabIndex)"
        case .generic:          return String(session.claudeSessionId.suffix(2))
        }
    }

    private func chipAccent(for session: Session) -> TaskChip.Accent {
        switch session.activity {
        case .waiting: return .amber
        case .thinking, .tool: return .blue
        default: return .green
        }
    }

    private func activityLabel(_ activity: Activity) -> String {
        switch activity {
        case .thinking:    return "Thinking"
        case .tool(let n): return n
        case .waiting:     return "Waiting for approval"
        case .done:        return "Done"
        case .initState:   return "Starting"
        case .idle:        return "Idle"
        }
    }
}
