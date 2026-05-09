import AppKit
import SwiftUI

struct NotchGeometry {
    let hasNotch: Bool
    let notchHeight: CGFloat       // ~32pt on notched MacBooks, 0 elsewhere
    let notchWidth: CGFloat        // approx 200pt centered, 0 if no notch
    let screenFrame: NSRect

    static func detect() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return NotchGeometry(hasNotch: false, notchHeight: 0, notchWidth: 0,
                                 screenFrame: .zero)
        }
        let topInset = screen.safeAreaInsets.top
        // macOS 12+ exposes the auxiliary menu-bar areas to the LEFT and RIGHT
        // of the notch. The space between them IS the notch.
        let auxLeft  = screen.auxiliaryTopLeftArea  ?? .zero
        let auxRight = screen.auxiliaryTopRightArea ?? .zero
        let measuredNotchWidth: CGFloat = {
            if topInset <= 0 { return 0 }
            if auxLeft.width > 0 && auxRight.width > 0 {
                let w = screen.frame.width - auxLeft.width - auxRight.width
                return max(w, 180)
            }
            return 220   // fallback for notched Macs where the API hasn't populated
        }()
        return NotchGeometry(
            hasNotch: topInset > 0,
            notchHeight: topInset,
            notchWidth: measuredNotchWidth,
            screenFrame: screen.frame
        )
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
