// agenttab/AgentTAB/UI/Rows/TabHeader.swift
import SwiftUI

struct TabHeader: View {
    let title: String           // "Zellij · Tab 2 · feat-auth"

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}
