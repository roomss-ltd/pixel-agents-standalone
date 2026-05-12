// ScreenTracker — publishes the NSScreen that the cursor is currently on.
// A global .mouseMoved monitor (no accessibility permission required) feeds
// a 150ms-debounced recompute. NotchPanel observes `$activeScreen` and
// reanchors itself on every change.
//
// Hot-plug: NSApplication.didChangeScreenParametersNotification fires when
// the display configuration changes (display added, removed, resolution
// change). We re-resolve at that moment so the panel doesn't end up
// anchored to a screen that no longer exists.

import AppKit
import Combine

@MainActor
final class ScreenTracker: ObservableObject {
    @Published private(set) var activeScreen: NSScreen

    private var mouseMonitor: Any?
    private var screenChangeObserver: NSObjectProtocol?
    private var pendingUpdate: DispatchWorkItem?

    init() {
        self.activeScreen = ScreenTracker.screenContainingCursor()
        startMouseMonitor()
        startScreenChangeObserver()
        AgentLog.screen.info("init activeScreen=\(self.activeScreen.localizedName, privacy: .public)")
    }

    deinit {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let o = screenChangeObserver { NotificationCenter.default.removeObserver(o) }
        pendingUpdate?.cancel()
    }

    // MARK: - Resolution

    /// Resolve the screen whose `frame` contains the current cursor
    /// position. Falls back to `NSScreen.main` (the screen with the
    /// menu bar) when nothing contains the cursor — happens briefly
    /// while the cursor crosses a bezel gap between displays.
    static func screenContainingCursor() -> NSScreen {
        let loc = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(loc) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
    }

    private func recomputeActiveScreen() {
        let candidate = ScreenTracker.screenContainingCursor()
        guard candidate != activeScreen else { return }
        let oldName = activeScreen.localizedName
        activeScreen = candidate
        AgentLog.screen.info("active screen changed \(oldName, privacy: .public) → \(candidate.localizedName, privacy: .public)")
    }

    // MARK: - Mouse-moved monitor (debounced)

    private func startMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleUpdate() }
        }
    }

    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recomputeActiveScreen() }
        pendingUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Hot-plug

    private func startScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                AgentLog.screen.info("display configuration changed; \(NSScreen.screens.count) screen(s)")
                // If the previously active screen disappeared, jump to
                // wherever the cursor is now (or NSScreen.main as fallback).
                if !NSScreen.screens.contains(self.activeScreen) {
                    self.activeScreen = ScreenTracker.screenContainingCursor()
                } else {
                    self.recomputeActiveScreen()
                }
            }
        }
    }
}
