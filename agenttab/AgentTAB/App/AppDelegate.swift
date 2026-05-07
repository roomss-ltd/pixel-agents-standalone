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
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit AgentTAB", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
