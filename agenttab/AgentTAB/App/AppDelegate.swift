import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var notchPanel: NotchPanel?
    var engine = ActivityEngine()
    let updater = UpdaterCoordinator()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "AT"
        statusItem?.menu = makeMenu()

        let geometry = NotchGeometry.detect()
        engine.start()

        // Build the panel first so we can capture it inside the SwiftUI callback below.
        let panel = NotchPanel(rootView: AnyView(EmptyView()))
        notchPanel = panel
        let rootView = NotchView(onExpandedChange: { [weak panel] expanded in
            panel?.isExpanded = expanded
        })
            .environment(\.notchGeometry, geometry)
            .environmentObject(engine)
        // Replace the placeholder with the real root view.
        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(rootView)
        } else {
            let host = NSHostingView(rootView: AnyView(rootView))
            host.frame = panel.contentLayoutRect
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
        }
        panel.anchorToNotch()
        panel.orderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notchPanel?.anchorToNotch()
        }

        let onboardingDone = UserDefaults.standard.bool(forKey: "AgentTAB.onboarding.completed")
        if !onboardingDone {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "AgentTAB Onboarding"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Restart", action: #selector(restart), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit AgentTAB", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restart() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
