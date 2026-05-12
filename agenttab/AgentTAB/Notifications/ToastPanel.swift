import AppKit
import SwiftUI

/// Legacy corner preference. Kept so existing settings storage and
/// the SettingsView picker keep compiling — toasts now always anchor
/// at the top-right (per the latest design spec).
enum ToastCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct Toast: Identifiable {
    let id = UUID()
    let variant: Variant
    let taskId: String       // chip label (e.g. "6.2")
    let projectName: String  // shown in the subline (truncated)
    let message: String      // e.g. "Waiting for approval", "Finished in 2m 14s"

    enum Variant {
        case attention   // amber — agent needs input
        case success     // green — task complete
    }
}

/// Top-right pinned, fixed-size toast panel. Always anchors at the top
/// right corner of the screen; the X button or the auto-dismiss timer
/// closes it.
@MainActor
final class ToastPanel: NSPanel {
    /// Fixed dimensions — match `ToastView`'s explicit frame.
    private static let toastSize = CGSize(width: 360, height: 62)
    /// Distance from the screen edges.
    private static let edgeInset: CGFloat = 16

    private var autoDismissTask: DispatchWorkItem?

    // MARK: - Engagement state machine
    //
    // The toast is normally passive — clicks redirect, the X dismisses,
    // the auto-dismiss timer fires after `duration`. A bare TAB binding
    // is too aggressive (TAB has meaning in every text-input app), so
    // we use a two-step flow:
    //
    //   1. Toast appears. Keyboard does nothing.
    //   2. User presses ⌥+TAB. Toast "engages" — visual highlight,
    //      4-second engagement window starts.
    //   3. Within that window:
    //        TAB → redirect + dismiss
    //        ESC → dismiss without redirect
    //        anything else → disengage (no action)
    //
    // This way TAB never collides with the focused app; the user has
    // to deliberately opt in via the modifier first.

    /// True while the toast is in the "engaged" state. Drives visual
    /// highlight and the local keyboard handlers.
    private var isEngaged: Bool = false

    /// Always-on while the toast is visible. Listens for the engagement
    /// hotkey (⌥+TAB).
    private var engagementHotkeyMonitor: Any?

    /// Only active while engaged. Listens for TAB / ESC / other.
    private var engagedKeyMonitor: Any?

    /// Auto-disengage if the user doesn't press TAB/ESC within this
    /// many seconds of engaging.
    private static let engagementTimeout: TimeInterval = 4
    private var disengageTimeout: DispatchWorkItem?

    /// Cached for re-rendering on engagement state change and for the
    /// hotkey monitors that need to call the same action as a click.
    private var currentToast: Toast?
    private var currentOnTap: (() -> Void)?

    // Keycodes.
    private static let tabKeyCode: UInt16 = 48
    private static let escKeyCode: UInt16 = 53
    private static let engagementMods: NSEvent.ModifierFlags = [.option]

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.toastSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        // Accept clicks so the X button works. Mouse over transparent
        // edges is harmless because the panel is exactly content-sized.
        self.ignoresMouseEvents = false
    }

    deinit {
        if let m = engagementHotkeyMonitor { NSEvent.removeMonitor(m) }
        if let m = engagedKeyMonitor { NSEvent.removeMonitor(m) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ toast: Toast, duration: TimeInterval, onTap: @escaping () -> Void = {}) {
        self.currentToast = toast
        self.currentOnTap = onTap
        self.isEngaged = false
        installContent()
        self.setContentSize(Self.toastSize)
        anchorTopRight()
        orderFront(nil)

        autoDismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.dismiss() }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)

        installEngagementHotkeyMonitor()
        AgentLog.notify.info("toast shown taskId=\(toast.taskId, privacy: .public)")
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        removeEngagementHotkeyMonitor()
        disengage()
        orderOut(nil)
        currentToast = nil
        currentOnTap = nil
    }

    /// Re-render the hosted ToastView with current `isEngaged` state.
    /// Called on show and on every engage / disengage transition so the
    /// visual highlight and subline reflect reality.
    private func installContent() {
        guard let toast = currentToast, let onTap = currentOnTap else { return }
        let view = ToastView(
            toast: toast,
            isEngaged: isEngaged,
            onClose: { [weak self] in self?.dismiss() },
            onTap:   { [weak self] in
                onTap()
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.toastSize)
        self.contentView = host
    }

    // MARK: - Engagement

    private func installEngagementHotkeyMonitor() {
        removeEngagementHotkeyMonitor()
        engagementHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard event.keyCode == Self.tabKeyCode else { return }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard mods == Self.engagementMods else { return }
                self.engage()
            }
        }
    }

    private func removeEngagementHotkeyMonitor() {
        if let m = engagementHotkeyMonitor {
            NSEvent.removeMonitor(m)
            engagementHotkeyMonitor = nil
        }
    }

    private func engage() {
        // Pressing ⌥+TAB again while already engaged is a confirm —
        // fire the redirect immediately. Saves the user a second keypress
        // for "I really mean it."
        if isEngaged {
            triggerRedirect()
            return
        }
        isEngaged = true
        installContent()
        installEngagedKeyMonitor()
        scheduleAutoDisengage()
        AgentLog.notify.info("toast engaged")
    }

    private func disengage() {
        guard isEngaged else { return }
        isEngaged = false
        disengageTimeout?.cancel()
        disengageTimeout = nil
        removeEngagedKeyMonitor()
        // Re-render so the subline returns to project · message and the
        // border highlight relaxes. Only if the toast hasn't been
        // dismissed already.
        if currentToast != nil {
            installContent()
        }
        AgentLog.notify.info("toast disengaged")
    }

    private func scheduleAutoDisengage() {
        disengageTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disengage() }
        disengageTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.engagementTimeout, execute: work)
    }

    private func triggerRedirect() {
        AgentLog.notify.info("toast redirect via engaged TAB")
        currentOnTap?()
        dismiss()
    }

    private func installEngagedKeyMonitor() {
        removeEngagedKeyMonitor()
        engagedKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.isEngaged else { return }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                switch event.keyCode {
                case Self.tabKeyCode where mods.isEmpty:
                    self.triggerRedirect()
                case Self.escKeyCode where mods.isEmpty:
                    AgentLog.notify.info("toast dismissed via engaged ESC")
                    self.dismiss()
                default:
                    // Any other key — including a modified TAB — exits
                    // the engaged state without firing the redirect, so
                    // the user can keep typing in their app without
                    // accidentally triggering it.
                    self.disengage()
                }
            }
        }
    }

    private func removeEngagedKeyMonitor() {
        if let m = engagedKeyMonitor {
            NSEvent.removeMonitor(m)
            engagedKeyMonitor = nil
        }
    }

    private func anchorTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - Self.toastSize.width - Self.edgeInset,
            y: visible.maxY - Self.toastSize.height - Self.edgeInset
        )
        setFrameOrigin(origin)
    }
}
