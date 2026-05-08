import SwiftUI

enum Theme {
    // Glass / chrome — ported from Hammerspoon claude-status.lua and webview/styles.lua
    static let glassBG     = Color(red: 0.09, green: 0.09, blue: 0.13).opacity(0.94)
    static let borderOuter = Color(white: 0.52).opacity(0.55)
    static let borderInner = Color.white.opacity(0.04)
    static let textPrimary = Color.white.opacity(0.88)
    static let textDim     = Color.white.opacity(0.35)
    static let rowEven     = Color.white.opacity(0.025)
    static let rowHighlight = Color.white.opacity(0.05)

    enum Activity {
        static let thinking  = Color(red: 0.45, green: 0.65, blue: 1.00)   // soft blue   #73A6FF
        static let tool      = Color(red: 1.00, green: 0.75, blue: 0.25)   // amber       #FFBF40
        static let waiting   = Color(red: 1.00, green: 0.55, blue: 0.35)   // orange      #FF8C59
        static let done      = Color(red: 0.45, green: 0.82, blue: 0.50)   // green       #73D280
        static let initState = Color(red: 0.55, green: 0.55, blue: 0.60)   // gray
        static let idle      = Color(red: 0.45, green: 0.82, blue: 0.50).opacity(0.5)
    }

    enum Animations {
        static let notch = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.78)
        static let coffeeSteamPeriod: Double = 4.8
        static let cardioPeriod: Double = 1.5
        static let waitingPulsePeriod: Double = 1.6
        static let completionFlashDuration: Double = 1.5
    }

    enum Layout {
        static let pillHeight: CGFloat = 32
        static let pillWidthCollapsed: CGFloat = 180
        static let expandedWidth: CGFloat = 380
        static let expandedMaxHeight: CGFloat = 460
        static let notchCarveCornerRadius: CGFloat = 10
        static let panelMaxWidth: CGFloat = 420
        static let panelMaxHeight: CGFloat = 460
    }
}

extension Activity {
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
}
