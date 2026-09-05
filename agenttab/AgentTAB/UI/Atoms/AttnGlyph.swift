// AttnGlyph.swift — pulsing amber warn triangle.
//
// Mirrors `notch.jsx:67-77`: drop-shadow goes 0 → 4px → 0 over 1.4s, infinite.

import SwiftUI

struct AttnGlyph: View {
    var size: CGFloat = 18
    var running: Bool = true

    @ViewBuilder
    var body: some View {
        if running {
            TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4
                glyph(glow: abs(sin(phase * .pi)))
            }
        } else {
            glyph(glow: 0.35)
        }
    }

    private func glyph(glow: Double) -> some View {
        WarnGlyph()
            .stroke(
                Theme.Neon.amber,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Theme.Neon.amber.opacity(0.85 * glow), radius: 4 * glow)
            .frame(width: size, height: size)
            .foregroundStyle(Theme.Neon.amber)
    }
}

#Preview {
    AttnGlyph(size: 22)
        .padding(40)
        .background(Color.black)
}
