import SwiftUI

@main
struct AgentTABApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("AgentTAB Settings (placeholder)")
                .frame(width: 400, height: 300)
        }
    }
}
