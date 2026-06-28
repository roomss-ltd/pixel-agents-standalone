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

    /// Neon palette. Sidequest is electric CYAN (playful), Low is neon yellow,
    /// Medium — the DEFAULT — is a calm BLUE so most agents read as neutral;
    /// only the ELEVATED levels alarm: High is VIOLET, Urgent a true red.
    var color: Color {
        switch self {
        case .sidequest: return Priority.neonCyan
        case .low:       return Priority.neonYellow
        case .medium:    return Priority.neonBlue
        case .high:      return Priority.neonViolet
        case .urgent:    return Priority.neonRed
        }
    }

    /// Saturated neon accents owned by Priority. Cyan/violet/red are chosen
    /// to sit far from the state hues (blue/amber/green) so priority and
    /// activity are always distinguishable at a glance.
    static let neonCyan   = Color(red: 0x18 / 255.0, green: 0xDC / 255.0, blue: 0xE8 / 255.0)
    static let neonYellow = Color(red: 0xFF / 255.0, green: 0xF5 / 255.0, blue: 0x70 / 255.0)
    static let neonViolet = Color(red: 0xA6 / 255.0, green: 0x6C / 255.0, blue: 0xFF / 255.0)
    static let neonBlue   = Color(red: 0x4D / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0)
    static let neonRed    = Color(red: 0xFF / 255.0, green: 0x4D / 255.0, blue: 0x4D / 255.0)
}
