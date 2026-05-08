// agenttab/AgentTAB/UI/NotchView.swift
import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine
    @State private var isHovered = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if isHovered {
                    expanded
                } else {
                    pill
                }
                Spacer()
            }
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
    }

    private var pill: some View {
        PillView()
            .onHover { hovering in isHovered = hovering }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 4) {
            if engine.sessions.isEmpty {
                Text("No active Claude sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.sessions) { session in
                    HStack {
                        Text(session.projectName).font(.system(size: 11, weight: .medium))
                        Text("·").foregroundStyle(.secondary)
                        Text(session.currentTool ?? activityLabel(session.activity))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in isHovered = hovering }
    }

    private var activeCount: Int {
        engine.sessions.filter {
            if case .thinking = $0.activity { return true }
            if case .tool = $0.activity { return true }
            return false
        }.count
    }
    private var doneCount: Int {
        engine.sessions.filter { $0.activity == .done }.count
    }
    private func activityLabel(_ a: Activity) -> String {
        switch a {
        case .thinking: return "Thinking…"
        case .tool(let n): return "Using \(n)"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .initState: return "Starting"
        case .idle: return "Idle"
        }
    }
}
