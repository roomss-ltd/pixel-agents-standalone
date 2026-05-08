// agenttab/AgentTAB/UI/ExpandedView.swift
import AppKit
import SwiftUI

struct ExpandedView: View {
    @EnvironmentObject var engine: ActivityEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Compact pill row at top (slightly shrunk to feel "secondary" inside the panel)
            PillView().scaleEffect(0.95)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if engine.sessions.isEmpty {
                        Text("No active Claude sessions")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                            .padding(12)
                    } else {
                        ForEach(groupedSessions, id: \.0) { (groupTitle, groupSessions) in
                            TabHeader(title: groupTitle)
                            ForEach(groupSessions) { session in
                                SessionRow(session: session) {
                                    handleClick(session)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: Theme.Layout.expandedMaxHeight - 80)
        }
        .frame(width: Theme.Layout.expandedWidth)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.panelBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.panelBorderOuter, lineWidth: 0.5)
        )
    }

    private var groupedSessions: [(String, [Session])] {
        let grouped = Dictionary(grouping: engine.sessions) { session -> String in
            switch session.terminalKind {
            case .zellij(let info): return "Zellij · Tab \(info.tabIndex) · \(info.tabName)"
            case .generic(let term): return term ?? "Other terminal"
            }
        }
        return grouped.sorted { $0.key < $1.key }
    }

    private func handleClick(_ session: Session) {
        switch session.terminalKind {
        case .zellij(let info):
            // Run zellij action focus-pane <id>
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["zellij", "action", "focus-pane", "\(info.paneId)"]
            try? task.run()
        case .generic:
            // Fallback: open project folder in Finder
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.projectPath)])
        }
    }
}
