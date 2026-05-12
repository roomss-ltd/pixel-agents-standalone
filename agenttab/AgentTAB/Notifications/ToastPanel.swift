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

    /// Global keyDown monitor that fires the toast's onTap action when
    /// the user presses TAB while the toast is visible. Lives only for
    /// the duration of one toast; recreated on every `show(_:)`.
    private var tabKeyMonitor: Any?

    /// Tab keycode on macOS. Matches `event.keyCode`.
    private static let tabKeyCode: UInt16 = 48

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
        if let m = tabKeyMonitor { NSEvent.removeMonitor(m) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ toast: Toast, duration: TimeInterval, onTap: @escaping () -> Void = {}) {
        // Recreate the hosting view so the X / tap closures capture
        // the current panel instance.
        let view = ToastView(
            toast: toast,
            onClose: { [weak self] in self?.dismiss() },
            onTap:   { [weak self] in
                onTap()
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.toastSize)
        self.contentView = host
        self.setContentSize(Self.toastSize)
        anchorTopRight()
        orderFront(nil)

        autoDismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.dismiss() }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)

        // While the toast is visible, an unmodified TAB triggers the
        // same redirect as clicking the toast. `addGlobalMonitorForEvents`
        // for keyDown requires Input Monitoring permission; if the user
        // hasn't granted it the callback simply never fires and the
        // click path is the only way to redirect. We don't suppress the
        // event — the focused app still receives the TAB — but the
        // collision window is small (5s per toast) and the user
        // explicitly opted into this binding.
        installTabKeyMonitor(onTap: onTap)
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        removeTabKeyMonitor()
        orderOut(nil)
    }

    private func installTabKeyMonitor(onTap: @escaping () -> Void) {
        removeTabKeyMonitor()
        tabKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == Self.tabKeyCode else { return }
            // Ignore Shift-Tab, ⌥-Tab, ⌃-Tab etc. — only bare TAB.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                AgentLog.notify.info("toast redirect via TAB")
                onTap()
                self.dismiss()
            }
        }
    }

    private func removeTabKeyMonitor() {
        if let m = tabKeyMonitor {
            NSEvent.removeMonitor(m)
            tabKeyMonitor = nil
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
