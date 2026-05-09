// Loaders.swift — SwiftUI ports of the ldrs.com variants the Hammerspoon
// implementation (and the React design canvas) cycle through.
//
// Each loader reads `currentColor` via `.foregroundStyle(color)` so a parent
// can recolor without mutating the loader. `RotatingLoader` swaps variants
// every 15s — same as `notch.jsx:RotatingLoader`.

import SwiftUI

// MARK: - Variant catalog

enum LoaderVariant: String, CaseIterable {
    case dotSpinner   = "dot-spinner"
    case quantum      = "quantum"
    case cardio       = "cardio"
    case trio         = "trio"
    // Note: the React canvas defines 9 variants (grid, chaotic-orbit,
    // hourglass, metronome, reuleaux). The four below cover the most
    // visually distinct shapes and are enough to demonstrate rotation.
    // Future work can port the rest line-by-line from `loaders.jsx`.
}

// MARK: - DotSpinner — 8 dots pulsing around a circle

struct DotSpinnerLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.0   // total cycle (loaders.jsx:14, speed * 1.111)

            ZStack {
                ForEach(0..<8) { i in
                    let phase = ((t / period) + Double(i) / 8.0).truncatingRemainder(dividingBy: 1)
                    let scale = 0.5 + 0.5 * abs(sin(phase * .pi))
                    Circle()
                        .fill(color)
                        .frame(width: size * 0.2, height: size * 0.2)
                        .opacity(0.5 + 0.5 * scale)
                        .scaleEffect(scale)
                        .offset(y: -size * 0.4)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Quantum — two concentric arcs spinning opposite directions

struct QuantumLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let outerAngle = (t * 360 / 1.75).truncatingRemainder(dividingBy: 360)
            let innerAngle = -(t * 360 / 1.75).truncatingRemainder(dividingBy: 360)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(color.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(outerAngle))

                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(color.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size * 0.56, height: size * 0.56)
                    .rotationEffect(.degrees(innerAngle))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Trio — three vertical bars bouncing

struct TrioLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 1.3

            HStack(spacing: size * 0.12) {
                ForEach(0..<3) { i in
                    let delay = Double(i) * 0.2
                    let phase = ((t + delay) / period).truncatingRemainder(dividingBy: 1)
                    // 40% of cycle bouncing up, rest scaled down (loaders.jsx:101)
                    let scale: CGFloat = phase < 0.4
                        ? 0.4 + 0.6 * (phase / 0.4)
                        : 1.0 - 0.6 * ((phase - 0.4) / 0.6)
                    Capsule()
                        .fill(color)
                        .frame(width: size * 0.22, height: size * 0.6)
                        .scaleEffect(y: scale, anchor: .bottom)
                }
            }
            .frame(width: size, height: size * 0.6)
        }
    }
}

// MARK: - Rotating loader — cycles variants every `intervalSeconds`

struct RotatingLoader: View {
    var size: CGFloat = 18
    var color: Color = Theme.Neon.blue
    var intervalSeconds: Double = Theme.Animations.loaderRotationSeconds

    @State private var index: Int = 0

    var body: some View {
        Group {
            switch LoaderVariant.allCases[index] {
            case .dotSpinner: DotSpinnerLoader(size: size, color: color)
            case .quantum:    QuantumLoader(size: size, color: color)
            case .cardio:     CardioLoader(color: color, size: size)
            case .trio:       TrioLoader(size: size, color: color)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            // Stagger initial pick so two RotatingLoaders mounted at the same
            // time don't show the same variant.
            index = Int.random(in: 0..<LoaderVariant.allCases.count)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                index = (index + 1) % LoaderVariant.allCases.count
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        DotSpinnerLoader(size: 28)
        QuantumLoader(size: 28)
        CardioLoader(size: 28)
        TrioLoader(size: 28)
        RotatingLoader(size: 28, intervalSeconds: 2)
    }
    .padding()
    .foregroundStyle(Theme.Neon.blue)
    .background(Color.black)
}
