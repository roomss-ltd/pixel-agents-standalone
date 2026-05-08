// agenttab/AgentTAB/UI/Rows/SessionRow.swift
import SwiftUI

struct SessionRow: View {
    let session: Session
    let onClick: () -> Void

    @State private var isHovered = false
    @State private var flashOpacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            iconForActivity
                .modifier(WaitingPulse(isActive: session.activity == .waiting))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(session.currentTool ?? activityLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Theme.rowHighlight : Color.clear)
        .overlay(
            Theme.Activity.done.opacity(flashOpacity)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        )
        .onChange(of: session.activity) { _, newValue in
            if newValue == .done {
                flashOpacity = 0.35
                withAnimation(.easeOut(duration: Theme.Animations.completionFlashDuration)) {
                    flashOpacity = 0
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Theme.Animations.notch) { isHovered = hovering } }
        .onTapGesture { onClick() }
    }

    @ViewBuilder
    private var iconForActivity: some View {
        switch session.activity {
        case .thinking:
            Circle().fill(Theme.Activity.thinking).frame(width: 8, height: 8)
        case .tool:
            Image(systemName: "bolt.fill").foregroundStyle(Theme.Activity.tool).font(.system(size: 12))
        case .waiting:
            Image(systemName: "pause.fill").foregroundStyle(Theme.Activity.waiting).font(.system(size: 12))
        case .done:
            Image(systemName: "checkmark").foregroundStyle(Theme.Activity.done).font(.system(size: 12))
        case .initState:
            Circle().fill(Theme.Activity.initState).frame(width: 6, height: 6)
        case .idle:
            Circle().stroke(Theme.Activity.idle, lineWidth: 1).frame(width: 6, height: 6)
        }
    }

    private var activityLabel: String {
        switch session.activity {
        case .thinking: return "Thinking…"
        case .tool(let n): return "Using \(n)"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .initState: return "Starting"
        case .idle: return "Idle"
        }
    }
}

struct WaitingPulse: ViewModifier {
    let isActive: Bool
    @State private var pulse: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? pulse : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: Theme.Animations.waitingPulsePeriod)
                    .repeatForever(autoreverses: true)) {
                    pulse = 1.15
                }
            }
            .onChange(of: isActive) { _, nowActive in
                if nowActive {
                    withAnimation(.easeInOut(duration: Theme.Animations.waitingPulsePeriod)
                        .repeatForever(autoreverses: true)) {
                        pulse = 1.15
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        pulse = 1.0
                    }
                }
            }
    }
}
