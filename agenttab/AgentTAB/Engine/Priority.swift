import SwiftUI

/// User-assigned priority for an agent tab — Jira / Linear style. The
/// user picks a level from a dropdown on each row; the expanded panel
/// can then sort by priority instead of recency.
///
/// `rawValue` is ordered ascending = lower → higher urgency, so
/// `a.rawValue > b.rawValue` is "a is more urgent than b". The raw
/// values are persisted to UserDefaults, so don't renumber them.
enum Priority: Int, CaseIterable, Codable {
    case sidequest = 0
    case low       = 1
    case medium    = 2
    case high      = 3
    case urgent    = 4

    /// Assigned to a session until the user picks something else.
    static let `default`: Priority = .medium

    var displayName: String {
        switch self {
        case .sidequest: return "Sidequest"
        case .low:       return "Low"
        case .medium:    return "Medium"
        case .high:      return "High"
        case .urgent:    return "Urgent"
        }
    }

    /// SF Symbol shown both in the row's priority chip and in each
    /// dropdown menu item.
    var systemImage: String {
        switch self {
        case .sidequest: return "moon.zzz.fill"
        case .low:       return "chevron.down"
        case .medium:    return "equal"
        case .high:      return "chevron.up"
        case .urgent:    return "exclamationmark.octagon.fill"
        }
    }

    /// Neon palette: Sidequest is white, Low is neon yellow, Medium +
    /// High are neon blue (Medium slightly dimmed so the pair still
    /// reads as a hierarchy), Urgent is neon red. All three accent
    /// hues are deliberately light, bright tones so they glow against
    /// the pitch-black panel.
    var color: Color {
        switch self {
        case .sidequest: return .white
        case .low:       return Priority.neonYellow
        case .medium:    return Priority.neonBlue.opacity(0.72)
        case .high:      return Priority.neonBlue
        case .urgent:    return Priority.neonRed
        }
    }

    /// Very light, bright neon accents owned by Priority — the Theme
    /// palette only has amber and a darker blue. Kept pale on purpose
    /// so the soft glow (see `AgentRow.priorityMenu`) reads as the
    /// accent rather than the fill.
    static let neonYellow = Color(red: 0xFF / 255.0, green: 0xFA / 255.0, blue: 0xB0 / 255.0)
    static let neonBlue   = Color(red: 0xB4 / 255.0, green: 0xDC / 255.0, blue: 0xFF / 255.0)
    static let neonRed    = Color(red: 0xFF / 255.0, green: 0xB6 / 255.0, blue: 0xB6 / 255.0)
}
