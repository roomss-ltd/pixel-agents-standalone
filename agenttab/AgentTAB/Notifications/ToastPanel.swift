import AppKit
import SwiftUI

enum ToastCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct Toast: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let activity: Activity
}

final class ToastPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ toast: Toast, corner: ToastCorner, duration: TimeInterval) {
        contentView = NSHostingView(rootView: ToastView(toast: toast))
        anchor(corner: corner)
        orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.orderOut(nil)
        }
    }

    private func anchor(corner: ToastCorner) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let pad: CGFloat = 16
        let myFrame = self.frame
        let origin: NSPoint
        switch corner {
        case .topLeft:     origin = NSPoint(x: f.minX + pad, y: f.maxY - myFrame.height - pad)
        case .topRight:    origin = NSPoint(x: f.maxX - myFrame.width - pad, y: f.maxY - myFrame.height - pad)
        case .bottomLeft:  origin = NSPoint(x: f.minX + pad, y: f.minY + pad)
        case .bottomRight: origin = NSPoint(x: f.maxX - myFrame.width - pad, y: f.minY + pad)
        }
        setFrameOrigin(origin)
    }
}
