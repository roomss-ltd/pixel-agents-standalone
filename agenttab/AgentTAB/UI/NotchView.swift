// agenttab/AgentTAB/UI/NotchView.swift
import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if isHovered {
                    ExpandedView()
                        .background(HoverTracker(onHover: { isHovered = $0 }))
                } else {
                    TwoPearlsView()
                        .background(HoverTracker(onHover: { isHovered = $0 }))
                }
                Spacer()
            }
            .padding(.top, geometry.notchHeight)   // pearls/expanded panel sit flush against notch bottom
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
    }
}
