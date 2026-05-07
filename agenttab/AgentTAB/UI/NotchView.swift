import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @State private var isHovered = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: isHovered ? 300 : 200,
                               height: isHovered ? 200 : 30)
                        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
                        .onHover { hovering in isHovered = hovering }
                    Text("hasNotch: \(geometry.hasNotch ? "yes" : "no") inset: \(Int(geometry.notchHeight))pt")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            Spacer()
        }
    }
}
