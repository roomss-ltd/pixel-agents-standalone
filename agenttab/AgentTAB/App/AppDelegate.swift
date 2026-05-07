import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var notchPanel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "AT"
        statusItem?.menu = makeMenu()

        let geometry = NotchGeometry.detect()
        notchPanel = NotchPanel(rootView: AnyView(
            NotchView()
                .environment(\.notchGeometry, geometry)
        ))
        notchPanel?.anchorToNotch()
        notchPanel?.orderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notchPanel?.anchorToNotch()
        }
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
