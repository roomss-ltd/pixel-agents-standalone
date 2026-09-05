// ToastView.swift — pitch-black notification toast that drops from the
// notch. Ports the `NotificationToast` design from `notch.jsx:530-591`:
//   * width 360pt fixed (height locked too so it never reflows)
//   * 0.5pt accent edge: amber for attention, green for success
//   * 14pt corner radius, drop shadow + accent inner ring + outer glow
//   * layout: TaskChip | title + monospace subline | activity icon | X
//   * X button dismisses; the toast surface taps through to focus the
//     originating zellij tab.
//   * border is an animated angular-gradient stroke that rotates a
//     bright sweep around the toast (4s cycle).

import SwiftUI

struct ToastView: View {
    let toast: Toast
    /// True while the user has explicitly engaged with the toast via
    /// ⌥+TAB. In that state we render brighter accents, scale up
    /// slightly, and swap the subline to a keyboard-hint string so the
    /// user knows TAB will redirect and ESC will dismiss.
    var isEngaged: Bool = false
    var onClose: () -> Void = {}
    var onTap:   () -> Void = {}

    var body: some View {
        // Single Button wraps the toast surface so the whole rectangle
        // is reliably tappable — nested .onTapGesture on subviews can
        // shadow each other and cause "sometimes doesn't redirect."
        // The dedicated X button is rendered ON TOP via .overlay so it
        // still captures its own click first.
        Button(action: onTap) {
            HStack(spacing: 10) {
                TaskChip(id: toast.taskId, accent: chipAccent, size: .sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Theme.textStrong)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subline)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                activityIcon
                    .frame(width: 16, height: 16)
                // Reserve space for the X overlay so the layout matches
                // the design even though the button is positioned over it.
                Color.clear.frame(width: 22, height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 360, height: 62)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(animatedBorder)
        // X overlay — sits on top of the Button surface in its own
        // hit-test zone (anchored to the trailing edge).
        .overlay(alignment: .trailing) {
            closeButton.padding(.trailing, 12)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
        .shadow(color: glowColor, radius: isEngaged ? 36 : 24)
        .scaleEffect(isEngaged ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isEngaged)
    }

    // MARK: - Animated border

    /// Angular-gradient stroke that rotates so a bright accent sweeps
    /// around the toast perimeter. 4s rotation feels alive without
    /// being distracting.
    private var animatedBorder: some View {
        TimelineView(.animation(minimumInterval: Theme.Animations.timelineMinimumInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 4) / 4) * 360
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: edgeColor.opacity(0.20), location: 0.00),
                            .init(color: edgeColor,                location: 0.20),
                            .init(color: glowColor,                location: 0.35),
                            .init(color: edgeColor.opacity(0.20), location: 0.55),
                            .init(color: edgeColor,                location: 0.75),
                            .init(color: edgeColor.opacity(0.20), location: 1.00),
                        ]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: 1.0
                )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var activityIcon: some View {
        switch toast.variant {
        case .attention:
            WarnGlyph()
                .stroke(Theme.Neon.amber,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        case .success:
            CheckGlyph()
                .stroke(Theme.Neon.green,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        case .urgentReminder:
            WarnGlyph()
                .stroke(Theme.Neon.pink,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
                .foregroundStyle(Theme.textDim)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived strings

    private var headline: String {
        switch toast.variant {
        case .attention:      return "AgentTab needs input"
        case .success:        return "Task complete"
        case .urgentReminder: return "Urgent agent still waiting"
        }
    }

    private var subline: String {
        if isEngaged {
            return "↵ TAB to open · ESC to dismiss"
        }
        return "\(toast.taskId) · \(toast.projectName) · \(toast.message)"
    }

    private var chipAccent: TaskChip.Accent {
        switch toast.variant {
        case .attention:      return .amber
        case .success:        return .green
        case .urgentReminder: return .pink
        }
    }

    private var accentBase: Color {
        switch toast.variant {
        case .attention:      return Theme.Neon.amber
        case .success:        return Theme.Neon.green
        case .urgentReminder: return Theme.Neon.pink
        }
    }

    private var edgeColor: Color {
        accentBase.opacity(isEngaged ? 1.0 : 0.85)
    }

    private var glowColor: Color {
        accentBase.opacity(isEngaged ? 0.45 : 0.20)
    }
}
