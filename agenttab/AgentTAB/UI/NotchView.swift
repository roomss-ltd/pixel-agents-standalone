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
                        .background(HoverTracker(onHover: { isHovered = $0 }))
                } else {
                    PillView()
                        .background(HoverTracker(onHover: { isHovered = $0 }))
                }
                Spacer()
            }
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
    }
}
