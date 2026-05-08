// agenttab/AgentTAB/UI/PillView.swift
import SwiftUI

struct PillView: View {
    @EnvironmentObject var engine: ActivityEngine
    @Environment(\.notchGeometry) var geometry

    var body: some View {
        HStack(spacing: 0) {
            loaderSlot
                .frame(width: 28)
                .padding(.leading, 14)

            Spacer().frame(width: max(geometry.notchWidth, 16))

            countsSlot
                .padding(.trailing, 14)
        }
        .frame(height: Theme.Layout.pillHeight)
        .background(
            NotchShape(notchWidth: geometry.notchWidth,
                       notchHeight: 0,    // pill drawn below notch, no top carve
                       cornerRadius: Theme.Layout.notchCarveCornerRadius)
                .fill(Theme.glassBG)
                .background(.ultraThinMaterial)
        )
        .overlay(
            NotchShape(notchWidth: geometry.notchWidth,
                       notchHeight: 0,
                       cornerRadius: Theme.Layout.notchCarveCornerRadius)
                .stroke(Theme.borderOuter, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var loaderSlot: some View {
        if hasActiveSession {
            CardioLoader(color: Theme.Activity.thinking, size: 24)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            CoffeeIdle(size: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var countsSlot: some View {
        HStack(spacing: 8) {
            if waitingCount > 0 {
                Label("\(waitingCount)", systemImage: "pause.fill")
                    .foregroundStyle(Theme.Activity.waiting)
            }
            if inProgressCount > 0 {
                Label("\(inProgressCount)", systemImage: "bolt.fill")
                    .foregroundStyle(Theme.Activity.tool)
            }
            if doneCount > 0 {
                Label("\(doneCount)", systemImage: "checkmark")
                    .foregroundStyle(Theme.Activity.done)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .contentTransition(.numericText())
    }

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
