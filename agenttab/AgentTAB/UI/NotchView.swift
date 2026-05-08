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
                    ExpandedView()
                        .onHover { hovering in isHovered = hovering }
                } else {
                    PillView()
                        .onHover { hovering in isHovered = hovering }
                }
                Spacer()
            }
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
    }
}
