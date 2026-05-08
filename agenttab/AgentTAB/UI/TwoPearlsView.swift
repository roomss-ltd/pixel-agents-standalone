// TwoPearlsView.swift — compact mode: two pitch-black pearls flanking the notch.
// Left pearl: cardio loader (active) or coffee idle (no activity).
// Right pearl: stacked count chips (⚡N, ⏸N, ✓N) only for non-zero counts.

import SwiftUI

struct TwoPearlsView: View {
    @EnvironmentObject var engine: ActivityEngine
    @Environment(\.notchGeometry) var geometry

    var body: some View {
        HStack(spacing: 0) {
            // LEFT pearl
            leftPearl
                .frame(width: Theme.Layout.leftPearlWidth, height: Theme.Layout.pearlHeight)

            // Spacer where the notch is. On non-notched Macs, fall back to a small fixed gap.
            Spacer()
                .frame(width: max(geometry.notchWidth, 16))

            // RIGHT pearl — width grows with the number of visible count chips.
            rightPearl
                .frame(minWidth: Theme.Layout.rightPearlWidthMin, minHeight: Theme.Layout.pearlHeight, maxHeight: Theme.Layout.pearlHeight)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - Left pearl: loader slot

    private var leftPearl: some View {
        ZStack {
            PearlShape(
                side: .left,
                outerCornerRadius: Theme.Layout.pearlOuterCornerRadius,
                innerCornerRadius: Theme.Layout.pearlInnerCornerRadius
            )
            .fill(Theme.panelBg)

            // The loader (cardio when active, coffee when idle) sits centered on the
            // outer half of the pearl so the inner curve doesn't crop it.
            HStack {
                Spacer().frame(width: 8)  // left padding inside outer round
                loaderSlot
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var loaderSlot: some View {
        if hasActiveSession {
            CardioLoader(color: Theme.Activity.thinking, size: 22)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .id("cardio")
        } else {
            CoffeeIdle(size: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .id("coffee")
        }
    }

    // MARK: - Right pearl: count chips

    private var rightPearl: some View {
        ZStack {
            PearlShape(
                side: .right,
                outerCornerRadius: Theme.Layout.pearlOuterCornerRadius,
                innerCornerRadius: Theme.Layout.pearlInnerCornerRadius
            )
            .fill(Theme.panelBg)

            HStack {
                Spacer()
                countsRow
                Spacer().frame(width: 8)  // right padding inside outer round
            }
        }
    }

    private var countsRow: some View {
        HStack(spacing: 6) {
            if waitingCount > 0 { countChip(icon: "pause.fill", count: waitingCount, kind: .waiting) }
            if inProgressCount > 0 { countChip(icon: "bolt.fill", count: inProgressCount, kind: .active) }
            if doneCount > 0 { countChip(icon: "checkmark", count: doneCount, kind: .done) }

            // When all counts are zero, render an inert dim dot so the pearl isn't empty.
            if waitingCount == 0 && inProgressCount == 0 && doneCount == 0 {
                Circle()
                    .fill(Theme.textMuted)
                    .frame(width: 4, height: 4)
            }
        }
        .font(.system(size: 10, weight: .heavy))   // matches Hammerspoon styles.lua:314 (font-weight 800)
        .contentTransition(.numericText())
    }

    private enum CountKind {
        case active, waiting, done
        var fg: Color {
            switch self {
            case .active:  return Theme.CountChip.activeText
            case .waiting: return Theme.CountChip.waitingText
            case .done:    return Theme.CountChip.doneText
            }
        }
    }

    private func countChip(icon: String, count: Int, kind: CountKind) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy))
            Text("\(count)")
        }
        .foregroundStyle(kind.fg)
    }

    // MARK: - Derived counts

    private var hasActiveSession: Bool {
        engine.sessions.contains { sess in
            switch sess.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }
    }

    private var inProgressCount: Int {
        engine.sessions.filter {
            if case .thinking = $0.activity { return true }
            if case .tool = $0.activity { return true }
            return false
        }.count
    }

    private var waitingCount: Int { engine.sessions.filter { $0.activity == .waiting }.count }
    private var doneCount: Int { engine.sessions.filter { $0.activity == .done }.count }
}
