// Theme.swift — palette + animation + layout constants.
//
// Ported from the AgentTab Figma-style design canvas (claude.ai/design,
// project agenttab). All RGB / RGBA values mirror the CSS custom properties
// declared at the top of `index.html` exactly. Cross-reference with
// `agenttab/project/index.html`, `notch.jsx`, and `loaders.jsx` if anything
// needs to be revisited.

import SwiftUI

enum Theme {
    // ── Panel / chrome ───────────────────────────────────────────
    /// Pure pitch black. The panel and the hardware notch share this color
    /// so they read as a single continuous shape.
    static let panelBg          = Color.black

    /// Subtle 0.5pt outline used on the expanded panel edge. Matches the
    /// `0 0 0 0.5px rgba(255,255,255,0.03)` shadow-as-stroke trick from the
    /// CSS prototype.
    static let panelBorderOuter = Color.white.opacity(0.03)
    static let panelBorderInner = Color.white.opacity(0.04)
    static let panelDivider     = Color.white.opacity(0.06)

    // ── Text ─────────────────────────────────────────────────────
    /// `--text: #f4f5f7`
    static let textStrong = Color(red: 0xF4/255.0, green: 0xF5/255.0, blue: 0xF7/255.0)
    /// `--text-dim: #8a8d96`
    static let textDim    = Color(red: 0x8A/255.0, green: 0x8D/255.0, blue: 0x96/255.0)
    /// `--text-faint: #5b5e66`
    static let textFaint  = Color(red: 0x5B/255.0, green: 0x5E/255.0, blue: 0x66/255.0)

    // Backwards-compatible aliases used by row code.
    static let textMuted  = textDim
    static let textRow    = textDim

    // ── Hairlines ────────────────────────────────────────────────
    /// `--hairline: rgba(255,255,255,0.07)`
    static let hairline       = Color.white.opacity(0.07)
    /// `--hairline-strong: rgba(255,255,255,0.12)`
    static let hairlineStrong = Color.white.opacity(0.12)

    // ── Neon accents ─────────────────────────────────────────────
    enum Neon {
        // Blue — `--neon-blue: #4ea1ff`
        static let blue       = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0)
        static let blueSoft   = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.16)
        static let blueEdge   = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.45)

        // Green — `--neon-green: #5be38a`
        static let green      = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0)
        static let greenSoft  = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.14)
        static let greenEdge  = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.40)

        // Amber — `--neon-amber: #ffae5b`
        static let amber      = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0)
        static let amberSoft  = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.18)
        static let amberEdge  = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.50)

        // Pink — urgent-finished reminder accent (#FF5BA8)
        static let pink       = Color(red: 0xFF/255.0, green: 0x5B/255.0, blue: 0xA8/255.0)
        static let pinkSoft   = Color(red: 0xFF/255.0, green: 0x5B/255.0, blue: 0xA8/255.0).opacity(0.18)
        static let pinkEdge   = Color(red: 0xFF/255.0, green: 0x5B/255.0, blue: 0xA8/255.0).opacity(0.50)
    }

    // ── Activity colors (state semantics) ────────────────────────
    enum Activity {
        static let thinking  = Neon.blue
        static let tool      = Neon.blue
        static let waiting   = Neon.amber
        static let done      = Neon.green
        static let initState = Color(white: 0.55)
        static let idle      = Neon.green.opacity(0.5)
    }

    // ── Row tint backgrounds (for the AgentTab card hover/active states) ──
    enum RowTint {
        // Active card — soft BLUE: a row is "active" while the agent is
        // currently processing. Matches the Neon.blue accent.
        static let activeBg     = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.06)
        static let activeBorder = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.30)

        // Attention card — soft amber.
        static let attentionBg     = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.06)
        static let attentionBorder = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.28)

        // Finished card — soft GREEN: only used once a session completes.
        static let finishedBg     = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.05)
        static let finishedBorder = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.22)

        // Resting (idle) card — barely-there hover lift, no green tint.
        static let restingBg     = Color.white.opacity(0.012)
        static let restingHover  = Color.white.opacity(0.030)
        static let restingBorder = Color.clear

        // Older row backwards-compat (legacy rows still reference these names).
        static let waitingBg     = attentionBg
        static let waitingBorder = attentionBorder
        static let completedBg   = finishedBg
        static let completedBorder = finishedBorder
    }

    // ── Task chip colors (the tab-id pill on each AgentTab card) ──
    enum Chip {
        // Green default — `notch.jsx:108`
        static let greenBg   = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.08)
        static let greenEdge = Color(red: 0x5B/255.0, green: 0xE3/255.0, blue: 0x8A/255.0).opacity(0.32)
        static let greenFg   = Neon.green

        // Blue — used for the header chip
        static let blueBg    = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.08)
        static let blueEdge  = Color(red: 0x4E/255.0, green: 0xA1/255.0, blue: 0xFF/255.0).opacity(0.35)
        static let blueFg    = Neon.blue

        // Amber — used on attention rows
        static let amberBg   = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.08)
        static let amberEdge = Color(red: 0xFF/255.0, green: 0xAE/255.0, blue: 0x5B/255.0).opacity(0.32)
        static let amberFg   = Neon.amber
    }

    // ── Count badges (the pills shown in the compact notch + expanded header) ──
    enum CountChip {
        // Active — `notch.jsx:82`
        static let activeText   = Neon.blue
        static let activeBg     = Neon.blueSoft
        static let activeBorder = Neon.blueEdge

        static let doneText     = Neon.green
        static let doneBg       = Neon.greenSoft
        static let doneBorder   = Neon.greenEdge

        static let waitingText  = Neon.amber
        static let waitingBg    = Neon.amberSoft
        static let waitingBorder = Neon.amberEdge
    }

    // Backwards-compat: legacy badge tokens used by the older SessionRow.
    enum Badge {
        static let activeBg      = Neon.blueSoft
        static let activeText    = Neon.blue.opacity(0.85)
        static let completedBg   = Neon.greenSoft
        static let completedText = Neon.green.opacity(0.85)
    }

    // ── Animations ───────────────────────────────────────────────
    enum Animations {
        static let notch = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.78)
        /// Pixel-art status animations stay legible at 8 FPS while avoiding
        /// display-rate SwiftUI redraws for every visible agent card.
        static let timelineMinimumInterval: Double = 1.0 / 8.0
        static let coffeeSteamPeriod: Double = 4.8
        static let cardioPeriod: Double = 1.5
        static let waitingPulsePeriod: Double = 1.6
        static let completionFlashDuration: Double = 1.5
        static let pearlExpandDuration: Double = 0.35
        /// Loader rotation period — matches the prototype's `intervalMs: 15000`.
        static let loaderRotationSeconds: Double = 15
    }

    // ── Layout constants ─────────────────────────────────────────
    enum Layout {
        // Compact notch — wider than the hardware notch so the icons flank
        // it, but tight: 2 counters on the left + 1 glyph on the right.
        // Lives entirely in the menu bar zone (no extension below).
        static let compactWidth: CGFloat = 320
        // Height matches the menu bar / notch height; the view falls back to
        // this constant when geometry.notchHeight isn't available.
        static let compactHeight: CGFloat = 34
        // Smaller corner radius reads as more "solid black" against the notch.
        static let compactCornerRadius: CGFloat = 12

        // Hover preview — `notch.jsx:174`.
        static let hoverWidth: CGFloat = 360
        static let hoverHeight: CGFloat = 86
        static let hoverCornerRadius: CGFloat = 20

        // Expanded panel — `notch.jsx:307`.
        static let expandedWidth: CGFloat = 720
        static let expandedHeight: CGFloat = 460
        static let expandedCornerRadius: CGFloat = 22

        // Status hairline at the top edge of every panel — 1.2pt tall, glow.
        static let statusHairlineHeight: CGFloat = 1.2
        static let statusHairlineInset: CGFloat = 14

        // AgentTab card — `notch.jsx:236`. Designed for 3-per-row in the 720pt panel.
        static let cardCornerRadius: CGFloat = 8
        static let cardPaddingH: CGFloat = 7
        static let cardPaddingV: CGFloat = 6
        static let cardHeight: CGFloat = 38

        // Task chip — `notch.jsx:113`.
        static let chipSmHeight: CGFloat = 26
        static let chipSmMinWidth: CGFloat = 38
        static let chipSmCornerRadius: CGFloat = 7
        static let chipXsHeight: CGFloat = 20
        static let chipXsMinWidth: CGFloat = 30
        static let chipXsCornerRadius: CGFloat = 5

        // Count badge — `notch.jsx:88-92`.
        static let countBadgeHeight: CGFloat = 20
        static let countBadgeRadius: CGFloat = 999

        // Section header dashes
        static let sectionLabelLetterSpacing: CGFloat = 2.0

        // Legacy row constants (kept so older code paths still compile while we
        // migrate). Newer code should use cardHeight / cardCornerRadius above.
        static let rowActiveHeight: CGFloat = 28
        static let rowCompletedHeight: CGFloat = 22
        static let rowGap: CGFloat = 6
        static let rowCornerRadius: CGFloat = 8
        static let rowHorizontalPadding: CGFloat = 7
        static let rowInternalGap: CGFloat = 7
        static let badgeMinWidth: CGFloat = 30
        static let badgeActiveHeight: CGFloat = 20
        static let badgeCompletedHeight: CGFloat = 20
        static let badgeCornerRadius: CGFloat = 5

        // Panel max size (NSPanel content rect). Must comfortably hold the
        // expanded panel plus a little breathing room below the menubar.
        static let panelMaxWidth: CGFloat = 760
        static let panelMaxHeight: CGFloat = 520
    }
}

extension Activity {
    /// Foreground color for the activity indicator.
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

    /// One-glyph icon string. Mirrors the Hammerspoon vocabulary used in row
    /// status labels (●, ⚡, ⏸, ✓).
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
