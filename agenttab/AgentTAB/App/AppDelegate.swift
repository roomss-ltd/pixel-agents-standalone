import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var notchPanel: NotchPanel?
    var engine = ActivityEngine()
    let updater = UpdaterCoordinator()
    let screenTracker = ScreenTracker()
    private var onboardingWindow: NSWindow?
    private var trackerCancellable: AnyCancellable?

    /// The SwiftUI root needs `notchGeometry` in the environment, and
    /// the geometry depends on which screen the notch is on. We keep the
    /// hosting view referenced so the subscription can swap a fresh
    /// rootView in whenever the active screen changes — that recomputes
    /// notch width/height/screenFrame everywhere down the tree.
    private weak var rootHostingView: NSHostingView<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "AT"
        statusItem?.menu = makeMenu()

        engine.start()

        let panel = NotchPanel(rootView: AnyView(EmptyView()))
        notchPanel = panel
        installRootView(for: screenTracker.activeScreen, into: panel)
        panel.reposition(to: screenTracker.activeScreen)
        panel.orderFront(nil)

        // Follow the cursor across displays. ScreenTracker debounces the
        // mouseMoved firehose to 150ms and only publishes when the
        // resolved screen actually changes.
        trackerCancellable = screenTracker.$activeScreen
            .sink { [weak self, weak panel] screen in
                guard let self, let panel else { return }
                self.installRootView(for: screen, into: panel)
                panel.reposition(to: screen)
            }

        let onboardingDone = UserDefaults.standard.bool(forKey: "AgentTAB.onboarding.completed")
        if !onboardingDone {
            showOnboarding()
        }
    }

    /// Rebuilds the SwiftUI root with geometry for the given screen and
    /// swaps it into the panel's hosting view. Called on launch and on
    /// every `activeScreen` change.
    private func installRootView(for screen: NSScreen, into panel: NotchPanel) {
        let geometry = NotchGeometry.detect(for: screen)
        let rootView = NotchView(onSizeChange: { [weak panel] size in
            panel?.liveSize = size
        })
            .environment(\.notchGeometry, geometry)
            .environmentObject(engine)

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(rootView)
            rootHostingView = hostingView
        } else {
            let host = NSHostingView(rootView: AnyView(rootView))
            host.frame = panel.contentLayoutRect
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            rootHostingView = host
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
