import SwiftUI

struct CardioLoader: View {
    var color: Color = Theme.Activity.thinking
    var size: CGFloat = 24

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let p = (elapsed / Theme.Animations.cardioPeriod).truncatingRemainder(dividingBy: 1)

            Canvas { ctx, canvasSize in
                let path = cardioPath(in: CGSize(width: canvasSize.width, height: canvasSize.height))

                // Trail: a fading window 0..p, 0.25 wide
                let trim = path.trimmedPath(from: max(0, p - 0.25), to: p)
                let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

                ctx.opacity = 0.2 + 0.8 * sin(p * .pi)   // fade in/out per cycle
                ctx.stroke(trim, with: .color(color), style: stroke)

                // Glow
                ctx.addFilter(.shadow(color: color.opacity(0.4), radius: 4))
                ctx.stroke(trim, with: .color(color), style: stroke)
            }
            .frame(width: size, height: size * 0.625)
        }
    }

    private func cardioPath(in s: CGSize) -> Path {
        // Path coords from l-cardio; viewBox 40 x 25, scaled to (s.width / 40)
        let scale = s.width / 40
        let y0 = 17.2 * scale
        var path = Path()
        path.move(to: CGPoint(x: 0.5 * scale, y: y0))
        path.addLine(to: CGPoint(x: 8.7 * scale, y: y0))
        path.addLine(to: CGPoint(x: 11.7 * scale, y: (17.2 - 4.7) * scale))
        path.addLine(to: CGPoint(x: 17.6 * scale, y: (17.2 - 4.7 + 12) * scale))
        path.addLine(to: CGPoint(x: 25.4 * scale, y: (17.2 - 4.7 + 12 - 24) * scale))
        path.addLine(to: CGPoint(x: 31.3 * scale, y: (17.2 - 4.7 + 12 - 24 + 16.7) * scale))
        path.addLine(to: CGPoint(x: 39.5 * scale, y: y0))
        return path
    }
}

#Preview {
    CardioLoader()
        .padding()
        .background(Color.black)
}
