// TaskChip.swift — JetBrains-Mono task identifier chip.
//
// Two sizes:
//   * `.sm` — 38pt min-width × 26pt high, 7pt corner — used in headers, hover preview
//   * `.xs` — 30pt min-width × 20pt high, 5pt corner — used inside AgentTab cards
//
// Mirrors `notch.jsx:103-123` exactly.

import SwiftUI

struct TaskChip: View {
    enum Accent { case green, blue, amber }
    enum Size { case sm, xs }

    let id: String
    var accent: Accent = .green
    var size: Size = .sm
    var muted: Bool = false

    var body: some View {
        Text(id)
            .font(font)
            .foregroundStyle(fgColor)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(edgeColor, lineWidth: 0.5)
            )
            .opacity(muted ? 0.7 : 1)
    }

    // MARK: - Geometry per size

    private var height: CGFloat {
        size == .xs ? Theme.Layout.chipXsHeight : Theme.Layout.chipSmHeight
    }

    private var minWidth: CGFloat {
        size == .xs ? Theme.Layout.chipXsMinWidth : Theme.Layout.chipSmMinWidth
    }

    private var corner: CGFloat {
        size == .xs ? Theme.Layout.chipXsCornerRadius : Theme.Layout.chipSmCornerRadius
    }

    private var horizontalPadding: CGFloat {
        size == .xs ? 6 : 8
    }

    private var font: Font {
        // JetBrains Mono with weight 600. Fallback to SF Mono if Inter family
        // isn't installed — the design loads it via Google Fonts but native
        // builds rely on whatever is on the system.
        let pointSize: CGFloat = size == .xs ? 11 : 12.5
        return Font.custom("JetBrainsMono-SemiBold", size: pointSize, relativeTo: .body)
            .monospaced()
    }

    private var fgColor: Color {
        switch accent {
        case .green: return Theme.Chip.greenFg
        case .blue:  return Theme.Chip.blueFg
        case .amber: return Theme.Chip.amberFg
        }
    }

    private var bgColor: Color {
        switch accent {
        case .green: return Theme.Chip.greenBg
        case .blue:  return Theme.Chip.blueBg
        case .amber: return Theme.Chip.amberBg
        }
    }

    private var edgeColor: Color {
        switch accent {
        case .green: return Theme.Chip.greenEdge
        case .blue:  return Theme.Chip.blueEdge
        case .amber: return Theme.Chip.amberEdge
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        TaskChip(id: "6.2", accent: .green)
        TaskChip(id: "7", accent: .blue)
        TaskChip(id: "4.1", accent: .amber)
        TaskChip(id: "3", size: .xs)
    }
    .padding()
    .background(Color.black)
}
