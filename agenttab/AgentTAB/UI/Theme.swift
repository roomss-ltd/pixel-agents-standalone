// Theme.swift — palette + animation + layout constants.
// All colors ported from claude-tab-status/hammerspoon/webview/styles.lua
// exactly (CSS RGBA values, line-by-line).

import SwiftUI

enum Theme {
    // ── Panel / chrome ────────────────────────────────────────
    // styles.lua:7-25 (--panel-bg etc.)
    /// The notch and our pearls/panel use the same pitch black so they
    /// visually merge with the MacBook's hardware notch.
    static let panelBg          = Color(red: 0,     green: 0,     blue: 0    )                 // pure black
    static let panelBorderOuter = Color(red: 0.502, green: 0.502, blue: 0.580).opacity(0.55)   // rgba(128,128,148,0.55)
    static let panelBorderInner = Color.white.opacity(0.04)                                     // rgba(255,255,255,0.04)
    static let panelDivider     = Color.white.opacity(0.06)

    static let textStrong = Color.white.opacity(0.88)                                           // --text-strong
    static let textMuted  = Color.white.opacity(0.35)                                           // --text-muted
    static let textRow    = Color.white.opacity(0.65)                                           // completed-row title

    // Row even/highlight backgrounds (subtle whites)
    static let rowEven      = Color.white.opacity(0.025)
    static let rowHighlight = Color.white.opacity(0.05)

    // ── Activity colors (state semantics) ─────────────────────
    enum Activity {
        // styles.lua:21 — --active-blue: rgb(115, 166, 255)
        static let thinking = Color(red: 115/255, green: 166/255, blue: 255/255)
        static let tool     = Color(red: 115/255, green: 166/255, blue: 255/255)   // Hammerspoon uses same blue for ⚡ and ●

        // styles.lua:23 — --waiting-orange: rgb(255, 140, 89)
        static let waiting = Color(red: 255/255, green: 140/255, blue:  89/255)

        // styles.lua:22 — --completed-green: rgb(115, 210, 128)
        static let done = Color(red: 115/255, green: 210/255, blue: 128/255)

        static let initState = Color(white: 0.55)
        static let idle      = Color(red: 115/255, green: 210/255, blue: 128/255).opacity(0.5)
    }

    // ── Row tint backgrounds (active/waiting/completed) ───────
    enum RowTint {
        // styles.lua:1178-1181 (active row)
        static let activeBg     = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.12)
        static let activeBorder = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.25)

        // styles.lua:1183-1186 (waiting row)
        static let waitingBg     = Color(red: 255/255, green: 140/255, blue: 89/255).opacity(0.12)
        static let waitingBorder = Color(red: 255/255, green: 140/255, blue: 89/255).opacity(0.25)

        // styles.lua:1188-1193 (completed row)
        static let completedBg     = Color(red: 115/255, green: 210/255, blue: 128/255).opacity(0.06)
        static let completedBorder = Color(red: 115/255, green: 210/255, blue: 128/255).opacity(0.12)
    }

    // ── Badge colors (tab number / pane number) ───────────────
    enum Badge {
        // styles.lua:1208-1224
        static let activeBg          = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.15)
        static let activeText        = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.85)
        static let completedBg       = Color(red: 115/255, green: 210/255, blue: 128/255).opacity(0.15)
        static let completedText     = Color(red: 115/255, green: 210/255, blue: 128/255).opacity(0.85)
    }

    // ── Count chip colors (used in right pearl + expanded header) ─
    enum CountChip {
        // styles.lua:322-332
        static let activeText   = Color(red: 115/255, green: 166/255, blue: 255/255)
        static let activeBg     = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.11)
        static let activeBorder = Color(red: 115/255, green: 166/255, blue: 255/255).opacity(0.18)

        static let doneText   = Color(red: 116/255, green: 204/255, blue: 139/255)
        static let doneBg     = Color(red: 116/255, green: 204/255, blue: 139/255).opacity(0.10)
        static let doneBorder = Color(red: 116/255, green: 204/255, blue: 139/255).opacity(0.16)

        static let waitingText   = Color(red: 255/255, green: 140/255, blue: 89/255)
        static let waitingBg     = Color(red: 255/255, green: 140/255, blue: 89/255).opacity(0.12)
        static let waitingBorder = Color(red: 255/255, green: 140/255, blue: 89/255).opacity(0.20)
    }

    // ── Animations ───────────────────────────────────────────
    enum Animations {
        static let notch = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.78)
        static let coffeeSteamPeriod: Double = 4.8           // styles.lua:238
        static let cardioPeriod: Double = 1.5
        static let waitingPulsePeriod: Double = 1.6          // styles.lua:1551
        static let completionFlashDuration: Double = 1.5
        static let pearlExpandDuration: Double = 0.35
    }

    // ── Layout constants ─────────────────────────────────────
    enum Layout {
        // Pearl geometry (compact mode — one on each side of the notch)
        static let pearlHeight: CGFloat = 26
        static let pearlOuterCornerRadius: CGFloat = 13      // half-height; fully rounded outer end
        // The inner (notch-facing) corner radius matches the notch carve so the pearl
        // "emerges" from the notch's bottom-left/right corner without a visible seam.
        static let pearlInnerCornerRadius: CGFloat = 10

        // Pearl widths — left has loader, right has counts.
        static let leftPearlWidth: CGFloat = 56
        static let rightPearlWidthMin: CGFloat = 56          // right pearl can grow if many counts shown

        // Expanded panel geometry
        static let expandedWidth: CGFloat = 340              // matches Hammerspoon detail view ~300pt + padding
        static let expandedMaxHeight: CGFloat = 460
        static let expandedBottomCornerRadius: CGFloat = 12  // styles.lua:14 --panel-radius
        static let expandedTopNotchCornerRadius: CGFloat = 10

        // Row geometry (Hammerspoon styles.lua:20-21, 1125-1130)
        static let rowActiveHeight: CGFloat = 28
        static let rowCompletedHeight: CGFloat = 22
        static let rowGap: CGFloat = 3
        static let rowCornerRadius: CGFloat = 6
        static let rowHorizontalPadding: CGFloat = 5
        static let rowInternalGap: CGFloat = 6

        // Badge geometry (styles.lua:1203-1206)
        static let badgeMinWidth: CGFloat = 22
        static let badgeActiveHeight: CGFloat = 18
        static let badgeCompletedHeight: CGFloat = 16
        static let badgeCornerRadius: CGFloat = 5

        // Panel max size (NSPanel content rect)
        static let panelMaxWidth: CGFloat = 480
        static let panelMaxHeight: CGFloat = 520
    }
}

extension Activity {
    /// Foreground color for the activity indicator dot/icon.
    var color: Color {
        switch self {
        case .thinking:  return Theme.Activity.thinking
        case .tool:      return Theme.Activity.tool
        case .waiting:   return Theme.Activity.waiting
        case .done:      return Theme.Activity.done
        case .initState: return Theme.Activity.initState
        case .idle:      return Theme.Activity.idle
        }
    }

    /// One-glyph icon string matching Hammerspoon: ●, ⚡, ⏸, ✓, etc.
    var iconGlyph: String {
        switch self {
        case .thinking:  return "\u{25CF}"  // ●
        case .tool:      return "\u{26A1}"  // ⚡
        case .waiting:   return "\u{23F8}"  // ⏸
        case .done:      return "\u{2713}"  // ✓
        case .initState: return ""
        case .idle:      return ""
        }
    }
}
