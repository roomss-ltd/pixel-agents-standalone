// FullscreenDetector — publishes the set of display IDs that currently
// have a fullscreen Space active. NotchPanel uses this in combination
// with ScreenTracker.activeScreen to decide whether to slide the bar
// out of the way (only on EXTERNAL displays in fullscreen — the
// built-in display always shows the bar).
//
// Detection: every 1 second we scan CGWindowListCopyWindowInfo for
// non-transparent layer-0 windows whose bounds cover an entire screen
// frame. In a real fullscreen Space the menu bar autohides and the
// window covers `screen.frame` (NOT `screen.visibleFrame`), which is
// what distinguishes it from a maximised non-fullscreen window.

import AppKit
import Combine
import CoreGraphics

@MainActor
final class FullscreenDetector: ObservableObject {
    @Published private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []

    private var observers: [NSObjectProtocol] = []
    private var scanWork: DispatchWorkItem?
    private let tolerance: CGFloat = 1.0

    init() {
        start()
    }

    deinit {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        for o in observers { ws.removeObserver(o); nc.removeObserver(o) }
    }

    private func start() {
        // First reading at launch so the panel doesn't briefly show in a
        // fullscreen Space before we've looked.
        scan()

        // Event-driven instead of a 1Hz poll: entering/leaving native
        // fullscreen ALWAYS switches the active Space (a fullscreen app gets
        // its own Space), so a space/app/display change is the only time the
        // answer can change. Idle CPU for this detector is now zero.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleScan() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScan() }
        })
    }

    /// Coalesce a burst of events, then scan once the transition has settled.
    /// A second scan a beat later catches the fullscreen animation finishing
    /// (window bounds don't reach `screen.frame` until the animation ends).
    private func scheduleScan() {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    private func scan() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            if !fullscreenDisplays.isEmpty {
                fullscreenDisplays = []
                AgentLog.screen.info("fullscreenDisplays cleared (no window info)")
            }
            return
        }

        var hits: Set<CGDirectDisplayID> = []
        for window in raw {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha > 0.95,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            // CGWindow bounds use top-left origin in flipped coordinates.
            // NSScreen.frame uses bottom-left in unflipped. Build a flipped
            // rect from the screen frame for comparison.
            for screen in NSScreen.screens {
                guard let id = displayID(for: screen) else { continue }
                let f = screen.frame
                // Flip Y: screen origin in the top-left coord system used
                // by CGWindow is (f.minX, primaryHeight - f.maxY). But
                // we only need width/height/origin equality in any
                // single coord system — match against CGWindow bounds
                // directly using the screen's width+height pinned to the
                // window's origin, since the window covers the whole
                // screen iff origin AND size match.
                let widthEq  = abs(bounds.width  - f.width)  <= tolerance
                let heightEq = abs(bounds.height - f.height) <= tolerance
                if widthEq && heightEq {
                    hits.insert(id)
                }
            }
        }

        if hits != fullscreenDisplays {
            let oldCount = fullscreenDisplays.count
            fullscreenDisplays = hits
            AgentLog.screen.info("fullscreenDisplays changed: \(oldCount) → \(hits.count) display(s)")
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID
    }
}

extension NSScreen {
    /// Convenience for callers that need the underlying CG display id
    /// (e.g. to look up membership in FullscreenDetector.fullscreenDisplays).
    var directDisplayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID
    }

    /// True for the built-in MacBook display. We never auto-hide on the
    /// built-in display — it's the user's home screen.
    var isBuiltIn: Bool {
        guard let id = directDisplayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }
}
