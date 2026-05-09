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

    enum Variant { case active, attention, finished, resting }

    @EnvironmentObject var engine: ActivityEngine
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
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

            statusIcon
                .frame(width: 20, height: 20)
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if isEdit {
                onUnlink()
            } else {
                onClick()
            }
        }
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
