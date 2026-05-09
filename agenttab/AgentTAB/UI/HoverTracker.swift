// agenttab/AgentTAB/UI/HoverTracker.swift
import AppKit
import SwiftUI

/// SwiftUI wrapper over NSTrackingArea with debounced enter/exit.
struct HoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void
    var enterDelay: TimeInterval = 0.06
    var exitDelay: TimeInterval = 0.0

    func makeNSView(context: Context) -> NSView {
        let view = TrackingNSView()
        view.onHover = onHover
        view.enterDelay = enterDelay
        view.exitDelay = exitDelay
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? TrackingNSView else { return }
        view.onHover = onHover
        view.enterDelay = enterDelay
        view.exitDelay = exitDelay
    }
}

private final class TrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    var enterDelay: TimeInterval = 0.06
    var exitDelay: TimeInterval = 0.0

    private var debounceTask: DispatchWorkItem?

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onHover?(true) }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + enterDelay, execute: task)
    }

    override func mouseExited(with event: NSEvent) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onHover?(false) }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay, execute: task)
    }
}
