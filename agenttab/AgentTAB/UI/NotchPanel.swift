import AppKit
import SwiftUI

/// Notch overlay panel.
///
/// CRITICAL behaviour: the panel covers a large transparent area at the top of
/// the screen, but only a small region (the pearls or the dropped-down expanded
/// panel) is actually visible. AppKit treats the entire panel frame as opaque
/// to mouse events by default — that means transparent regions of the panel
/// silently eat clicks meant for whatever app is below (browser, Xcode, etc.).
///
/// The fix: keep `ignoresMouseEvents = true` by default (clicks pass through),
/// and toggle it to `false` only while the cursor is actually over visible
/// content. We track the cursor with `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`
/// which fires for any mouse movement on screen even when AgentTAB isn't the
/// active application — exactly what we need for an `LSUIElement` background app.
final class NotchPanel: NSPanel {
    /// Whether the SwiftUI hierarchy is currently in expanded mode. Drives the
    /// size of the live (clickable) region. Updated by `NotchView` when it
    /// transitions between compact pearls and the expanded dropdown.
    var isExpanded: Bool = false {
        didSet { updateClickability(force: true) }
    }

    private var mouseMonitor: Any?

    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
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
        // Start click-through. The mouse monitor flips this off only when the
        // cursor is over visible content. See `updateClickability(force:)`.
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = self.contentLayoutRect
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        startMouseMonitor()
    }

    deinit {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func anchorToNotch() {
        guard let screen = NSScreen.main else { return }
        let topInset = screen.safeAreaInsets.top
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 480

        // Top-center of screen, panel hanging down from menu bar / notch.
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        UserDefaults.standard.set(Double(topInset), forKey: "AgentTAB.lastNotchInset")

        // Re-evaluate live region after frame change.
        updateClickability(force: true)
    }

    // MARK: - Click-through region management

    private func startMouseMonitor() {
        // `addGlobalMonitorForEvents` for mouse events does NOT require
        // accessibility permission (only keyboard events do). Mouse position is
        // unprivileged information.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateClickability(force: false)
        }
        // Set initial state (in case the cursor is already over the panel area).
        DispatchQueue.main.async { [weak self] in
            self?.updateClickability(force: true)
        }
    }

    /// Compute the screen-coordinate rect that represents the visible UI.
    /// Compact: a strip across the top containing the two pearls.
    /// Expanded: a wider/taller region for the dropdown panel.
    private func liveRegion() -> NSRect {
        let panelFrame = self.frame
        let topInset = NSScreen.main?.safeAreaInsets.top ?? 0
        // The pearls / expanded panel sit flush against the notch's bottom edge,
        // which is `topInset` below the screen top.
        let topEdge = panelFrame.maxY - topInset

        if isExpanded {
            // Expanded panel: ~480pt wide × ~460pt tall, centered horizontally.
            let w: CGFloat = 480
            let h: CGFloat = 460
            return NSRect(
                x: panelFrame.midX - w / 2,
                y: topEdge - h,
                width: w,
                height: h
            )
        } else {
            // Compact: notch-flanking pearls. ~340pt wide × ~32pt tall directly below the notch.
            // Slightly tall (40pt) so cursor entering from below still triggers.
            let w: CGFloat = 360
            let h: CGFloat = 40
            return NSRect(
                x: panelFrame.midX - w / 2,
                y: topEdge - h,
                width: w,
                height: h
            )
        }
    }

    private func updateClickability(force: Bool) {
        let cursor = NSEvent.mouseLocation
        let region = liveRegion()
        let shouldBeLive = region.contains(cursor)
        let target = !shouldBeLive
        if force || self.ignoresMouseEvents != target {
            self.ignoresMouseEvents = target
        }
    }
}
