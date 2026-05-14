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

    /// Neon palette per the user's spec: Sidequest + Low are yellow,
    /// Medium + High are blue, Urgent is red. Within each colour pair
    /// the lower level is slightly dimmed so the hierarchy still reads
    /// at a glance even though the hue is shared.
    var color: Color {
        switch self {
        case .sidequest: return Priority.neonYellow.opacity(0.62)
        case .low:       return Priority.neonYellow
        case .medium:    return Theme.Neon.blue.opacity(0.62)
        case .high:      return Theme.Neon.blue
        case .urgent:    return Priority.urgentRed
        }
    }

    /// Neon yellow — the Theme palette only has amber (orange-ish), so
    /// Priority owns its own bright yellow.
    static let neonYellow = Color(red: 0xFF / 255.0, green: 0xE0 / 255.0, blue: 0x4E / 255.0)
    /// Urgent gets its own red — the Theme palette stops at amber.
    static let urgentRed = Color(red: 0xFF / 255.0, green: 0x5B / 255.0, blue: 0x5B / 255.0)
}
