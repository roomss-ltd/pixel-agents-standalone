import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        self.ignoresMouseEvents = false
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = self.contentLayoutRect
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func anchorToNotch() {
        guard let screen = NSScreen.main else { return }
        let topInset = screen.safeAreaInsets.top
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 460

        // Anchor: top center of the screen, panel hanging down from menu bar / notch
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight
        // Note: AppKit uses bottom-left origin, so subtracting from maxY puts the top edge of the panel at the top of the screen

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        // Store inset for SwiftUI to query
        UserDefaults.standard.set(Double(topInset), forKey: "AgentTAB.lastNotchInset")
    }
}
