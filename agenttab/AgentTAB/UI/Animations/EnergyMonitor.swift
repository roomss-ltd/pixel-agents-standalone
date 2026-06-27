// EnergyMonitor.swift — battery-aware gating for decorative animation.
//
// AgentTAB is an always-on overlay, so any continuously-ticking
// `TimelineView(.animation)` (breathing idle creatures, steam, attention
// pulses) redraws at the display refresh rate — 60Hz, or 120Hz on ProMotion —
// for as long as it is on screen, even when nothing visible changes. That is
// the dominant battery cost of an idle overlay.
//
// `DecorativeTimeline` replaces `TimelineView(.animation)` for those decorative
// loops. It does two things:
//   1. Drops the cadence from display-rate to a chosen `fps` (a slow breathing
//      animation does not need 120fps) via `.periodic`.
//   2. Freezes entirely — rendering a single static frame with NO clock — when
//      `EnergyMonitor.shared.quiet` is true: the screens are asleep (user can't
//      see it), Low Power Mode is on, or the user asked for Reduce Motion.

import AppKit
import Combine
import SwiftUI

/// Shared, app-wide "should decorative motion run?" signal. One tiny object;
/// every `DecorativeTimeline` observes it, so a single sleep / Low-Power /
/// Reduce-Motion change pauses all decorative animation at once.
///
/// Not `@MainActor`: notifications are delivered on the main queue and the
/// only mutation (`quiet`) happens in those handlers, so observers see changes
/// on the main thread without actor annotation (which would otherwise snag the
/// `.shared` default value used by `DecorativeTimeline`).
final class EnergyMonitor: ObservableObject {
    static let shared = EnergyMonitor()

    /// True ⇒ decorative animations should freeze to a static frame.
    @Published private(set) var quiet: Bool = false

    private var screensAsleep = false

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default

        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true; self?.recompute()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false; self?.recompute()
        }
        // Reduce Motion toggle.
        ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.recompute()
        }
        // Low Power Mode toggle.
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                       object: nil, queue: .main) { [weak self] _ in
            self?.recompute()
        }
        recompute()
    }

    private func recompute() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let next = screensAsleep || lowPower || reduceMotion
        if next != quiet { quiet = next }
    }
}

/// The per-tick value handed to a `DecorativeTimeline` closure. Mirrors
/// `TimelineView`'s context just enough that call sites using `ctx.date` need
/// no body changes. Deliberately NOT nested inside the generic view — a nested
/// type would depend on the view's `Content` parameter and deadlock inference
/// (the closure's parameter type would depend on the very type being inferred
/// from its return value).
struct DecorativeTick { let date: Date }

/// Drop-in replacement for `TimelineView(.animation)` for DECORATIVE loops.
/// Same closure shape (`{ ctx in … ctx.date … }`), but ticks at `fps` instead
/// of the display refresh rate, and freezes to a static frame while the app is
/// `quiet` (asleep / Low Power / Reduce Motion).
struct DecorativeTimeline<Content: View>: View {
    private let fps: Double
    private let content: (DecorativeTick) -> Content

    @ObservedObject private var energy = EnergyMonitor.shared
    @State private var anchor = Date()

    init(fps: Double = 15, @ViewBuilder content: @escaping (DecorativeTick) -> Content) {
        self.fps = fps
        self.content = content
    }

    var body: some View {
        if energy.quiet {
            // Static — no clock, no redraws. Hold a fixed frame.
            content(DecorativeTick(date: anchor))
        } else {
            TimelineView(.periodic(from: anchor, by: 1.0 / max(1, fps))) { ctx in
                content(DecorativeTick(date: ctx.date))
            }
        }
    }
}
