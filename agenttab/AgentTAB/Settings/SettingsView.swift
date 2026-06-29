import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            UpdatesSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettings: View {
    @AppStorage("AgentTAB.openAtLogin") var openAtLogin = false
    @State private var hooksInstalled = HookInstaller.hooksInstalled
    @State private var hookError: String?

    var body: some View {
        Form {
            Toggle("Open AgentTAB at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    if on { LoginItem.register() } else { LoginItem.unregister() }
                }
            Section("Session tracking") {
                Toggle("Precise tracking (Claude Code hooks)", isOn: $hooksInstalled)
                    .onChange(of: hooksInstalled) { _, on in
                        do {
                            if on { try HookInstaller.install() }
                            else   { try HookInstaller.uninstall() }
                            hookError = nil
                        } catch {
                            hookError = error.localizedDescription
                            hooksInstalled = HookInstaller.hooksInstalled   // snap back to the truth
                        }
                    }
                Text("ON: registers a tiny hook in ~/.claude/settings.json so AgentTAB gets exact tool / permission events — accurate state for every tool. OFF: read-only transcript fallback (can mis-flag long tools like `make` as “waiting”). Fully reversible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hookError {
                    Text(hookError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
    }
}

struct NotificationsSettings: View {
    @AppStorage("AgentTAB.toast.corner") var toastCorner: String = ToastCorner.bottomRight.rawValue
    @AppStorage("AgentTAB.notifications.enabled") var notificationsEnabled: Bool = true
    @AppStorage("AgentTAB.sounds.enabled") var soundsEnabled: Bool = true
    @AppStorage("AgentTAB.sounds.waitingReminder") var waitingReminder: Bool = true
    @AppStorage("AgentTAB.notch.waitingPulse") var waitingPulse: Bool = true

    var body: some View {
        Form {
            Toggle("Show notifications", isOn: $notificationsEnabled)
            Picker("Toast position", selection: $toastCorner) {
                Text("Top left").tag(ToastCorner.topLeft.rawValue)
                Text("Top right").tag(ToastCorner.topRight.rawValue)
                Text("Bottom left").tag(ToastCorner.bottomLeft.rawValue)
                Text("Bottom right").tag(ToastCorner.bottomRight.rawValue)
            }
            .disabled(!notificationsEnabled)
            Toggle("Notification sounds", isOn: $soundsEnabled)
            Toggle("Waiting reminder every 30s", isOn: $waitingReminder)
            Toggle("Waiting pulse", isOn: $waitingPulse)
        }
        .padding()
    }
}

struct UpdatesSettings: View {
    var body: some View {
        Form {
            Button("Check for updates now") {
                (NSApp.delegate as? AppDelegate)?.updater.checkForUpdates()
            }
            Text("Updates are signed with EdDSA. AgentTAB checks once per day in the background and prompts when a new version is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct AdvancedSettings: View {
    @State private var showConfirm = false

    var body: some View {
        Form {
            Section("Diagnostics") {
                Button("Reveal hook script in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([HookInstaller.hookScriptPath])
                }
                Button("Reveal support directory in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([HookInstaller.supportDir])
                }
            }
            Section("Danger zone") {
                Button("Uninstall AgentTAB…") { showConfirm = true }
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .alert("Uninstall AgentTAB?", isPresented: $showConfirm) {
            Button("Uninstall", role: .destructive) { performUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AgentTAB will remove its hooks from ~/.claude/settings.json (preserving any other hooks), delete its support directory, and unregister itself from Login Items. The app file in /Applications must be deleted manually — Finder will open to it.")
        }
    }

    private func performUninstall() {
        // 1. Reverse hook merge in ~/.claude/settings.json
        try? HookInstaller.uninstall()

        // 2. Remove the support directory
        try? FileManager.default.removeItem(at: HookInstaller.supportDir)

        // 3. Unregister Login Item
        LoginItem.unregister()

        // 4. Reset onboarding flag so a fresh install re-prompts
        UserDefaults.standard.removeObject(forKey: "AgentTAB.onboarding.completed")
        UserDefaults.standard.removeObject(forKey: "AgentTAB.dropInMode")

        // 5. Reveal /Applications/AgentTAB.app in Finder so the user can drag to Trash
        let appURL = URL(fileURLWithPath: "/Applications/AgentTAB.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }

        // 6. Quit AgentTAB
        NSApp.terminate(nil)
    }
}
