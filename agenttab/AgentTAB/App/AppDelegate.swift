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
    let fullscreenDetector = FullscreenDetector()
    let tokenTracker = TokenTracker()
    private var onboardingWindow: NSWindow?
    private var trackerCancellable: AnyCancellable?
    private var autoHideCancellable: AnyCancellable?

    /// Geometry of the most recently installed root view. macOS replaces
    /// NSScreen instances on every Space / fullscreen swipe, which
    /// republishes `activeScreen`; we use this to skip rebuilding the
    /// SwiftUI root when the physical display + notch geometry are
    /// unchanged (the swipe-flicker fix).
    private var lastInstalledGeometry: NotchGeometry?

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
        tokenTracker.start()

        let panel = NotchPanel(rootView: AnyView(EmptyView()))
        notchPanel = panel
        installRootView(for: screenTracker.activeScreen, into: panel)
        panel.reposition(to: screenTracker.activeScreen)
        lastInstalledGeometry = NotchGeometry.detect(for: screenTracker.activeScreen)
        panel.orderFront(nil)

        // Follow the cursor across displays. ScreenTracker debounces the
        // mouseMoved firehose to 150ms and only publishes when the
        // resolved screen actually changes.
        trackerCancellable = screenTracker.$activeScreen
            .sink { [weak self, weak panel] screen in
                guard let self, let panel else { return }
                // macOS hands out fresh NSScreen instances on every Space /
                // fullscreen swipe, so `activeScreen` republishes even when the
                // display and notch geometry are identical. Rebuilding the
                // SwiftUI root on those swaps is what makes the panel flicker
                // mid-swipe — only rebuild when the geometry actually changes
                // (different display, resolution change, notch dims change).
                let geometry = NotchGeometry.detect(for: screen)
                if geometry != self.lastInstalledGeometry {
                    self.lastInstalledGeometry = geometry
                    self.installRootView(for: screen, into: panel)
                    panel.reposition(to: screen)
                }
                self.evaluateAutoHide(panel: panel)
            }

        // Phase 2 — auto-hide on external-display fullscreen.
        // Combine the cursor screen and the fullscreen set: if the
        // active screen is external AND that display is currently
        // running a fullscreen Space, slide the panel out of the way.
        autoHideCancellable = Publishers.CombineLatest(
            screenTracker.$activeScreen,
            fullscreenDetector.$fullscreenDisplays
        )
        .sink { [weak panel] _, _ in
            guard let panel else { return }
            // Defer to next runloop so reposition() runs first when both
            // publishers fire on the same tick.
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.evaluateAutoHide(panel: panel)
            }
        }

        let onboardingDone = UserDefaults.standard.bool(forKey: "AgentTAB.onboarding.completed")
        if !onboardingDone {
            showOnboarding()
        }
    }

    /// Predicate that decides the panel's visibility. Built-in display
    /// is always visible. External display + fullscreen on that
    /// display → auto-hide. Anything else → visible.
    private func evaluateAutoHide(panel: NotchPanel) {
        let screen = screenTracker.activeScreen
        let isExternal = !screen.isBuiltIn
        let displayID = screen.directDisplayID
        let isFullscreen = displayID.map { fullscreenDetector.fullscreenDisplays.contains($0) } ?? false

        // Auto-hide-on-external-fullscreen only makes sense when the external
        // is a SECONDARY glance-screen — i.e. the built-in MacBook display is
        // also active (lid open). In clamshell mode (lid closed) or on a
        // desktop Mac, no built-in display is present, so the external IS the
        // home screen and must keep the notch even in fullscreen apps.
        let hasBuiltInActive = NSScreen.screens.contains { $0.isBuiltIn }

        if isExternal && isFullscreen && hasBuiltInActive {
            panel.autoHide()
        } else {
            panel.autoShow()
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
            .environmentObject(tokenTracker)

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
