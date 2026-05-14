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
    private var edgeHoverMonitor: Any?
    private var hotkeyMonitor: Any?
    private var menuBeginObserver: NSObjectProtocol?
    private var menuEndObserver: NSObjectProtocol?

    /// True while an NSMenu spawned from inside the panel (the per-row
    /// priority dropdown, the footer "⋯" menu) is open. The menu popup
    /// is a separate window outside the panel's live region, so without
    /// this guard:
    ///   * the mouse-moved monitor would flip `ignoresMouseEvents` true
    ///     (cursor is "outside" → panel goes click-through), and
    ///   * the global-click monitor would treat the menu-item click as
    ///     a "click outside → collapse" signal.
    /// While set, both monitors leave the panel state untouched.
    private var isMenuTracking = false

    // MARK: - Visibility (Phase 2)

    enum Visibility { case visible, hidden, peeking }

    private(set) var visibility: Visibility = .visible

    /// The Y origin the panel sits at while .visible. We cache it on each
    /// reposition() so the slide animation can return to the right spot
    /// even if the active screen changed while hidden.
    private var visibleY: CGFloat = 0
    private var currentScreen: NSScreen?

    /// Cursor at top-edge of the active screen for this long → peek.
    private static let edgeHoldSeconds: TimeInterval = 0.25
    /// How long peek stays before re-hiding after the cursor leaves.
    private static let peekHoldAfterLeave: TimeInterval = 3
    /// Hotkey peek duration.
    private static let peekHoldHotkey: TimeInterval = 5

    private var edgeHoldStarted: Date?
    private var pendingRehide: DispatchWorkItem?

    /// ⌃⌥A → 0x00 (A keyCode) with .control + .option modifiers.
    private static let hotkeyKeyCode: UInt16 = 0x00
    private static let hotkeyMods: NSEvent.ModifierFlags = [.control, .option]

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
        startPeekRequestObserver()
        startMenuTrackingObservers()
    }

    private func startMenuTrackingObservers() {
        menuBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isMenuTracking = true }
        }
        menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Hold the guard briefly past the menu closing — the
                // selection click's leftMouseDown is delivered around
                // the same instant the menu ends tracking, and it must
                // still be covered or it'll collapse the panel.
                try? await Task.sleep(for: .milliseconds(200))
                self?.isMenuTracking = false
            }
        }
    }

    private var peekObserver: NSObjectProtocol?

    private func startPeekRequestObserver() {
        peekObserver = NotificationCenter.default.addObserver(
            forName: .agentTabRequestPeek,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.visibility != .visible {
                    self.peek(duration: NotchPanel.peekHoldHotkey)
                }
            }
        }
    }

    deinit {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = edgeHoverMonitor { NSEvent.removeMonitor(m) }
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m) }
        if let o = peekObserver { NotificationCenter.default.removeObserver(o) }
        if let o = menuBeginObserver { NotificationCenter.default.removeObserver(o) }
        if let o = menuEndObserver { NotificationCenter.default.removeObserver(o) }
        pendingRehide?.cancel()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Anchoring

    func anchorToNotch() {
        guard let screen = NSScreen.main else { return }
        reposition(to: screen)
    }

    /// Reanchor to a specific screen. Called from the ScreenTracker
    /// subscription so the panel follows the cursor across displays.
    /// We jump rather than animate — animating across screens with
    /// different resolutions and scales looks broken (the panel
    /// appears to leap diagonally and snap into place).
    func reposition(to screen: NSScreen) {
        let topInset = screen.safeAreaInsets.top
        let screenFrame = screen.frame

        let panelWidth: CGFloat = Theme.Layout.panelMaxWidth
        let panelHeight: CGFloat = Theme.Layout.panelMaxHeight
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight

        currentScreen = screen
        visibleY = y

        // If we're currently hidden / peeking on the new screen, keep
        // that state — repositioning shouldn't force-reveal the panel.
        let targetY: CGFloat
        switch visibility {
        case .visible, .peeking:
            targetY = y
        case .hidden:
            targetY = y + panelHeight + 8
        }

        self.setFrame(NSRect(x: x, y: targetY, width: panelWidth, height: panelHeight),
                      display: true, animate: false)

        UserDefaults.standard.set(Double(topInset), forKey: "AgentTAB.lastNotchInset")
        updateClickability(force: true)
        AgentLog.panel.info("anchored to screen=\(screen.localizedName, privacy: .public) hasNotch=\(topInset > 0) visibility=\(String(describing: self.visibility), privacy: .public)")
    }

    // MARK: - Auto-hide / peek (Phase 2)

    /// External-display fullscreen requested the panel to disappear.
    func autoHide() {
        guard visibility != .hidden else { return }
        animateTo(visible: false)
        visibility = .hidden
        installEdgeHoverMonitor()
        installHotkeyMonitor()
        AgentLog.panel.info("autoHide")
    }

    /// Conditions for auto-hide no longer apply (left fullscreen, moved
    /// to built-in display, etc.) — fully restore.
    func autoShow() {
        guard visibility != .visible else { return }
        pendingRehide?.cancel()
        pendingRehide = nil
        removeEdgeHoverMonitor()
        removeHotkeyMonitor()
        animateTo(visible: true)
        visibility = .visible
        AgentLog.panel.info("autoShow")
    }

    /// Slide the panel down briefly while still in auto-hide mode.
    /// Triggered by top-edge hover, hotkey, or toast tap.
    func peek(duration: TimeInterval = NotchPanel.peekHoldAfterLeave) {
        guard visibility != .visible else { return }
        animateTo(visible: true)
        visibility = .peeking
        schedulePeekEnd(after: duration)
        AgentLog.panel.info("peek duration=\(duration)")
    }

    private func schedulePeekEnd(after seconds: TimeInterval) {
        pendingRehide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visibility == .peeking else { return }
            self.animateTo(visible: false)
            self.visibility = .hidden
        }
        pendingRehide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func animateTo(visible: Bool) {
        guard let screen = currentScreen else { return }
        let frame = self.frame
        let targetY: CGFloat = visible
            ? visibleY
            : visibleY + frame.height + 8
        let target = NSRect(x: frame.origin.x, y: targetY, width: frame.width, height: frame.height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        }
        _ = screen   // silence unused warning when targetY uses visibleY only
    }

    // MARK: - Edge-hover & hotkey monitors (Phase 2)

    private func installEdgeHoverMonitor() {
        guard edgeHoverMonitor == nil else { return }
        edgeHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluateEdgeHover() }
        }
    }

    private func removeEdgeHoverMonitor() {
        if let m = edgeHoverMonitor {
            NSEvent.removeMonitor(m)
            edgeHoverMonitor = nil
        }
        edgeHoldStarted = nil
    }

    private func evaluateEdgeHover() {
        guard visibility == .hidden, let screen = currentScreen else { return }
        let loc = NSEvent.mouseLocation
        guard screen.frame.contains(loc) else { edgeHoldStarted = nil; return }
        let nearTop = loc.y >= screen.frame.maxY - 2
        if nearTop {
            if let start = edgeHoldStarted {
                if Date().timeIntervalSince(start) >= NotchPanel.edgeHoldSeconds {
                    edgeHoldStarted = nil
                    peek(duration: NotchPanel.peekHoldAfterLeave)
                }
            } else {
                edgeHoldStarted = Date()
            }
        } else {
            edgeHoldStarted = nil
        }
    }

    private func installHotkeyMonitor() {
        guard hotkeyMonitor == nil else { return }
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.keyCode == NotchPanel.hotkeyKeyCode,
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask) == NotchPanel.hotkeyMods {
                    self.peek(duration: NotchPanel.peekHoldHotkey)
                }
            }
        }
    }

    private func removeHotkeyMonitor() {
        if let m = hotkeyMonitor {
            NSEvent.removeMonitor(m)
            hotkeyMonitor = nil
        }
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
        // While a menu spawned from the panel is open the cursor is over
        // the menu popup (outside `liveRegion()`). Leave the panel as it
        // was — flipping to click-through here would break the menu
        // interaction and collapse the panel.
        guard !isMenuTracking else { return }
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
                // A click on a menu item spawned from the panel is not
                // a "click outside" — don't collapse on it.
                guard !self.isMenuTracking else { return }
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
