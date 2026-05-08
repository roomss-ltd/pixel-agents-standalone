import SwiftUI

/// A rounded-bottom pill with an optional notch carve at the top center.
/// Top corners curve INWARD (toward the notch's bottom edges) when notch is present.
struct NotchShape: Shape {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let nw = notchWidth
        let centerX = rect.midX

        // Start: top-left of pill
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

        if nw > 0 {
            // Top edge: line up to where the notch carve begins
            let notchLeft = centerX - nw / 2
            let notchRight = centerX + nw / 2
            path.addLine(to: CGPoint(x: notchLeft - r, y: rect.minY))
            // Carve in: curve down to the notch's bottom edge
            path.addQuadCurve(
                to: CGPoint(x: notchLeft, y: rect.minY + r),
                control: CGPoint(x: notchLeft, y: rect.minY)
            )
            // Bottom of notch (straight across)
            path.addLine(to: CGPoint(x: notchRight, y: rect.minY + r))
            // Carve out: curve back up
            path.addQuadCurve(
                to: CGPoint(x: notchRight + r, y: rect.minY),
                control: CGPoint(x: notchRight, y: rect.minY)
            )
        }

        // Top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        // Top-left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        NotchShape(notchWidth: 200, notchHeight: 32, cornerRadius: 10)
            .fill(Theme.panelBg)
            .frame(width: 420, height: 100)
        NotchShape(notchWidth: 0, notchHeight: 0, cornerRadius: 10)
            .fill(Theme.panelBg)
            .frame(width: 320, height: 50)
    }
    .padding(40)
    .background(Color.gray)
}
