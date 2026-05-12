# AgentTAB — Multi-Surface Polish

Design doc for three workstreams flagged from real-world use:

- **Phase 0** — Defensive session-state hardening (invisible; safe to ship without repro data).
- **Phase 1** — Multi-monitor follow-cursor (notch jumps to the screen the user is on).
- **Phase 2** — Fullscreen-on-external auto-hide (slides out of the way during presentations on an external display, stays put on the built-in display).

A fourth workstream — concrete macOS 26.2 bug fixes — is **blocked** on a debug bundle from the affected machine and is not designed here. Phase 0 is the part of that work that can ship without repro data, because every fix is defensive (tighter invariants, not bug-specific patches).

Build order: 0 → 1 → 2. Phase 2 reuses the `ScreenTracker` introduced in Phase 1.

---

## Phase 0 — Defensive session-state hardening

### Symptoms reported
1. Repeated "Task complete" notifications for an agent that wasn't running.
2. RECENTLY ACTIVE vs OLDER FINISHED buckets drift on macOS 26.2.

### Root-cause hypotheses
Both trace back to `ActivityEngine` and the JSONL/Zellij ingestion paths:

- `notifySessionStateChange` fires on any `oldActivity → newActivity` flip. If the engine recomputes state from a re-read of an unchanged source file, it can re-flip and re-notify.
- `JSONLWatcher` re-emits historical lines on rescan; `TranscriptParser.handleSystem` does not track which `turn_duration` events it has already consumed.
- `applyZellijUpdate` falls back to `Date()` for `lastUpdate` when `elapsedSeconds(from:)` returns `nil` — that stamp moves a "done 3 hours ago" agent into the RECENTLY ACTIVE bucket on every scan.

### Defensive changes (no repro needed)

1. **Notification dedupe key.** Per-session `lastNotifiedTransition: (from: Activity, to: Activity, firedAt: Date)`. Refuse to fire the same `(from, to)` for the same session within 30 seconds. Reset on a different transition.

2. **Notify only on source-of-truth change.**
   - JSONL: gate `notifySessionStateChange` on the most recent line's timestamp being strictly newer than the last seen for that session.
   - Zellij: gate on the status file's `updated_at` being strictly newer than the last seen for that pane.
   - Never notify from an engine-internal recomputation that wasn't triggered by a source-file change.

3. **`lastUpdate` integrity.** Audit every site that writes `session.lastUpdate`:
   - In `applyZellijUpdate`, when `elapsedSeconds(from:)` returns `nil`, **keep the previous `lastUpdate`** instead of stamping `now`. Emit a one-shot warning log per pane.
   - In `JSONLWatcher`, derive `lastUpdate` from the last *newly seen* line's timestamp, not the file's `mtime`.

4. **JSONL byte-offset idempotency.** `JSONLWatcher` tracks `parsedBytes: [URL: UInt64]`. On rescan, only parse from `parsedBytes[file]` onward; advance after each batch. Eliminates re-emission of historical `turn_duration` events.

5. **Global notification throttle.** Belt-and-braces: a session may produce at most one notification per 60 seconds, regardless of dedupe key. Drops are logged.

6. **Structured logging.** `Logger(subsystem: "com.roomss.agenttab", category: "engine")` lines on:
   - every state transition (with previous, next, source, file path)
   - every notification fire (with dedupe outcome)
   - every `elapsedSeconds(from:)` failure
   These show up in `log show --predicate 'process == "AgentTAB"'` and make future debug bundles answer the question directly instead of requiring guesswork.

### Files touched

- `agenttab/AgentTAB/Engine/ActivityEngine.swift` — dedupe key, source-of-truth gate, throttle, logging, `lastUpdate` integrity in `applyZellijUpdate`.
- `agenttab/AgentTAB/Engine/JSONL/JSONLWatcher.swift` — `parsedBytes` map, only emit new lines.
- `agenttab/AgentTAB/Engine/JSONL/TranscriptParser.swift` — make `handleSystem` idempotent on duplicate `turn_duration`.

### Open questions
None blocking. Confirm 30s dedupe window and 60s throttle are acceptable defaults.

---

## Phase 1 — Multi-monitor follow-cursor

### Goal
Notch appears on whichever screen the user's cursor is currently on. Today the panel is anchored to a single screen for the app's lifetime.

### Design

**New component:** `Engine/ScreenTracker.swift`

```swift
@MainActor
final class ScreenTracker: ObservableObject {
    @Published private(set) var activeScreen: NSScreen
    private var monitor: Any?
    private var debounce: DispatchWorkItem?

    init() {
        activeScreen = NSScreen.main ?? NSScreen.screens[0]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.scheduleUpdate()
        }
    }

    private func scheduleUpdate() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recomputeActiveScreen() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func recomputeActiveScreen() {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) else { return }
        if screen != activeScreen { activeScreen = screen }
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}
```

**`NotchPanel` integration:**
- Inject `ScreenTracker` via `AppDelegate`.
- Subscribe to `$activeScreen` (Combine) and reposition on change.
- Reposition = recompute frame origin so the panel is top-center of the new screen.

```swift
func reposition(to screen: NSScreen) {
    let f = screen.frame
    let size = self.frame.size
    let origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height)
    setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
}
```

### Screens without a hardware notch
External monitors have no cutout. Two options:
- **(a)** Render the bar at top-center as a floating capsule. The existing `CompactBarShape` already renders correctly without a physical notch behind it.
- **(b)** Hide on non-notch screens and stay on whichever screen has the notch.

**Recommendation: (a)** — the feature value is "tracks where I'm looking." (b) defeats the purpose on dual-external setups.

Hardware-notch detection: `screen.safeAreaInsets.top > 0` (macOS 12+).

### Animation
Jumping (no animation) recommended. Cross-screen animations look broken because resolutions and scales differ — the panel appears to leap diagonally and snap. Test on hardware; revisit if it feels jarring.

### Files touched
- `agenttab/AgentTAB/Engine/ScreenTracker.swift` — new.
- `agenttab/AgentTAB/UI/NotchPanel.swift` — observe + reposition.
- `agenttab/AgentTAB/UI/Geometry.swift` — `notchWidth` must be recomputed per active screen; fallback to a fixed 200pt width on non-notch screens.
- `agenttab/AgentTAB/App/AppDelegate.swift` — own the `ScreenTracker`, pass it into `NotchPanel`.

### Open questions
1. Animate the reposition or jump? **Recommend jump.**
2. Debounce window — 150ms feels right; tune on hardware.
3. Behavior on hot-plug (`NSApplication.didChangeScreenParametersNotification`): re-resolve `activeScreen` and reposition.

---

## Phase 2 — Fullscreen-on-external auto-hide

### Goal
When presenting from an external monitor in fullscreen (Keynote, Zoom share, browser kiosk), the notch slides out of the way. On the built-in display, it never hides — that's the user's normal workspace.

### Design

**New component:** `Engine/FullscreenDetector.swift`

Polls every 1 second (cheap — single `CGWindowListCopyWindowInfo` call) and publishes:

```swift
@Published private(set) var fullscreenScreens: Set<CGDirectDisplayID>
```

Detection algorithm:
1. `let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`
2. For each window with `kCGWindowLayer == 0` (normal app):
   - Read `kCGWindowBounds` → CGRect.
   - Find the screen whose `frame == bounds` within 1pt tolerance.
   - If found, mark that screen's `CGDirectDisplayID` as fullscreen.
3. Cross-check: the built-in display always shows its menu bar; in a real fullscreen Space the menu bar autohides, so the window covers the *whole* `screen.frame` (not `screen.visibleFrame`).

`CGDirectDisplayID` per `NSScreen`: `screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID`.

### Behavior matrix

| Screen   | Fullscreen on that screen? | Behavior                                                              |
|----------|----------------------------|-----------------------------------------------------------------------|
| Built-in | any                        | Visible (normal).                                                     |
| External | no                         | Visible (Phase 1 follow-cursor applies).                              |
| External | yes                        | Hidden — panel slid up off-screen. Peek trigger reveals it for ~3 s.  |

Notifications (toasts) are independent of the notch's hidden state — they still appear.

### Hide / peek animation
- Hide: `NSAnimationContext` 220 ms ease-in-out, slide the panel frame above the screen top by `panelHeight + 8 pt`. Set `alphaValue = 0` at the end.
- Peek: reverse animation, hold for 3 s after the cursor leaves, then re-hide.

### Peek trigger — **decision needed**
Three candidates:
- **(a)** Top-edge hover: cursor at `y >= activeScreen.maxY - 2 pt` for 250 ms.
- **(b)** Global hotkey: e.g. ⌃⌥A toggles peek for 5 s.
- **(c)** Both.

**Recommendation: (c).** Edge-hover handles "let me glance"; hotkey handles "I heard a toast, take me to it" and is accessibility-friendly. Implementing both is ~20 extra lines.

### Files touched
- `agenttab/AgentTAB/Engine/FullscreenDetector.swift` — new.
- `agenttab/AgentTAB/UI/NotchPanel.swift` — `isHidden` state, slide animation, top-edge monitor (`NSEvent.addGlobalMonitorForEvents` with `.mouseMoved`).
- `agenttab/AgentTAB/App/AppDelegate.swift` — own the `FullscreenDetector`, optional hotkey registration via `NSEvent.addGlobalMonitorForEvents` with `.keyDown` + modifier check.

### Open questions
1. Peek trigger choice — see above.
2. Hotkey itself — ⌃⌥A is unused on a default install; confirm it doesn't conflict with anything you use.
3. Should the toast tap-redirect (which calls `engine.focus`) auto-peek the notch too? Probably yes.

---

## Build & ship order

| Step | Workstream                                          | Status   |
|------|-----------------------------------------------------|----------|
| 1    | Phase 0 — defensive engine hardening                | Ready    |
| 2    | Phase 1 — multi-monitor follow-cursor               | Ready    |
| 3    | Phase 2 — fullscreen-on-external auto-hide          | Ready (1 decision pending) |
| 4    | macOS 26.2 specific bug fixes                       | Blocked on debug bundle |

Each step is committable independently and ships behind no flags — these are corrections / additions to existing behavior, not opt-in features.

---

## Decisions still needed

| # | Question | Recommended default |
|---|----------|---------------------|
| 1 | Phase 1: animate reposition across screens, or jump? | Jump |
| 2 | Phase 2: peek trigger — edge hover, hotkey, or both? | Both |
| 3 | Phase 2: hotkey identity (if used) — ⌃⌥A? | ⌃⌥A |
| 4 | Phase 0: 30 s dedupe window + 60 s global throttle? | Yes |

If you're happy with the recommended defaults, no further input needed — I can ship 0 → 1 → 2 straight through.

---

## Out of scope (for now)

- Notarisation / Developer-ID signing (separate workstream; requires paid Apple account).
- The DMG path (`scripts/dmg-to-desktop.sh`) — colleague-install path is `make install`, which is already fixed.
- Toast redesign — the current toast is the design we want.
- Hammerspoon parity audits — not requested.
