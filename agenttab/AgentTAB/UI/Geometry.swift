import AppKit
import SwiftUI

struct NotchGeometry: Equatable {
    let hasNotch: Bool
    let notchHeight: CGFloat       // ~32pt on notched MacBooks, 0 elsewhere
    let notchWidth: CGFloat        // ~200pt centered on notched MacBooks; on
                                   // external displays we synthesise a
                                   // 200pt-wide top-center capsule region.
    let screenFrame: NSRect

    /// Width to use for the synthetic "notch" zone on screens that
    /// don't have a hardware cutout (external displays, non-notch
    /// Macs). Keeps the UI proportions identical so the bar reads the
    /// same on every screen.
    static let syntheticNotchWidth: CGFloat = 200

    /// Build geometry for a SPECIFIC screen (multi-monitor follow-cursor).
    /// Use this from `ScreenTracker.$activeScreen.sink { … }`.
    static func detect(for screen: NSScreen) -> NotchGeometry {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0 {
            // Notched MacBook display: measure the cutout from
            // auxiliaryTop{Left,Right}Area when populated.
            let auxLeft  = screen.auxiliaryTopLeftArea  ?? .zero
            let auxRight = screen.auxiliaryTopRightArea ?? .zero
            let measured: CGFloat
            if auxLeft.width > 0 && auxRight.width > 0 {
                measured = max(screen.frame.width - auxLeft.width - auxRight.width, 180)
            } else {
                measured = 220   // notched but API hasn't populated yet
            }
            return NotchGeometry(
                hasNotch: true,
                notchHeight: topInset,
                notchWidth: measured,
                screenFrame: screen.frame
            )
        }
        // Non-notch screen: render a synthetic top-center capsule region.
        // hasNotch stays false so views that draw "around" a hardware notch
        // can branch on it, but `notchWidth` is non-zero so the bar
        // proportions match the notched case.
        return NotchGeometry(
            hasNotch: false,
            notchHeight: 0,
            notchWidth: syntheticNotchWidth,
            screenFrame: screen.frame
        )
    }

    /// Convenience for legacy callers that didn't know about multiple
    /// screens. Resolves the screen with the menu bar.
    static func detect() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return NotchGeometry(hasNotch: false, notchHeight: 0, notchWidth: 0,
                                 screenFrame: .zero)
        }
        return detect(for: screen)
    }
}

private struct NotchGeometryKey: EnvironmentKey {
    static let defaultValue = NotchGeometry(hasNotch: false, notchHeight: 0,
                                            notchWidth: 0, screenFrame: .zero)
}

extension EnvironmentValues {
    var notchGeometry: NotchGeometry {
        get { self[NotchGeometryKey.self] }
        set { self[NotchGeometryKey.self] = newValue }
    }
}
