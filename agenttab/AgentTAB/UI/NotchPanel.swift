// NotchPanel.swift — borderless statusBar-level NSPanel that hosts the
// SwiftUI hierarchy. It covers a large transparent area at the top of the
// screen but only a small region (the visible UI) should accept clicks —
// AppKit treats the entire panel frame as opaque to mouse events by default,
// which would steal clicks from the apps below.
//
// The fix: keep `ignoresMouseEvents = true` by default and toggle it to
// `false` only while the cursor is inside the live region (the rect occupied
// by whatever view phase is currently visible). Mouse position monitoring
// uses `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` which does NOT
// require accessibility permission — only keyboard monitors do.

import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    /// Live size of the visible UI. Updated by `NotchView` via the
    /// `onSizeChange` callback — controls the click-through region.
    var liveSize: CGSize = CGSize(
        width: Theme.Layout.compactWidth,
        height: Theme.Layout.compactHeight
    ) {
        didSet { updateClickability(force: true) }
    }

    private var mouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Theme.Layout.panelMaxWidth,
                height: Theme.Layout.panelMaxHeight
            ),
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
        startGlobalClickMonitor()
        startEscMonitor()
    }

    deinit {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Anchoring

    func anchorToNotch() {
        guard let screen = NSScreen.main else { return }
        let topInset = screen.safeAreaInsets.top
        let screenFrame = screen.frame

        // Top-center, large enough for the largest panel size. The shape
        // hangs below the notch — `liveSize` controls clickable area.
        let panelWidth: CGFloat = Theme.Layout.panelMaxWidth
        let panelHeight: CGFloat = Theme.Layout.panelMaxHeight
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        UserDefaults.standard.set(Double(topInset), forKey: "AgentTAB.lastNotchInset")
        updateClickability(force: true)
    }

    // MARK: - Click-through region

    private func startMouseMonitor() {
        // `addGlobalMonitorForEvents` for mouse events does NOT require
        // accessibility permission (only keyboard events do).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateClickability(force: false) }
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateClickability(force: true)
        }
    }

    /// Screen-coordinate rect occupied by the currently-visible UI.
    ///
    /// The compact panel sits in the menu bar zone (top of screen). The
    /// expanded panel extends from the top of the screen down by its full
    /// rendered height (including the bit hidden behind the notch). Either
    /// way, the live region's TOP edge is at `panelFrame.maxY` (top of
    /// screen) and the height is whatever NotchView reports.
    private func liveRegion() -> NSRect {
        let panelFrame = self.frame
        return NSRect(
            x: panelFrame.midX - liveSize.width / 2,
            y: panelFrame.maxY - liveSize.height,
            width: liveSize.width,
            height: liveSize.height
        )
    }

    private func updateClickability(force: Bool) {
        let cursor = NSEvent.mouseLocation
        let region = liveRegion()
        let target = !region.contains(cursor)
        if force || self.ignoresMouseEvents != target {
            self.ignoresMouseEvents = target
        }
    }

    // MARK: - Click-outside / Esc collapse

    private func startGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cursor = NSEvent.mouseLocation
                if !self.liveRegion().contains(cursor) {
                    NotificationCenter.default.post(name: .agentTabRequestCollapse, object: nil)
                }
            }
        }
    }

    private func startEscMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {  // Esc
                NotificationCenter.default.post(name: .agentTabRequestCollapse, object: nil)
                return nil
            }
            return event
        }
    }
}
