import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            UpdatesSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettings: View {
    @AppStorage("AgentTAB.openAtLogin") var openAtLogin = false

    var body: some View {
        Form {
            Toggle("Open AgentTAB at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    if on { LoginItem.register() } else { LoginItem.unregister() }
                }
            Section("Mode") {
                Text(EnvironmentProbe.detect().isDropInCandidate
                     ? "Drop-in (read-only)"
                     : "Managed hooks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct NotificationsSettings: View {
    @AppStorage("AgentTAB.toast.corner") var toastCorner: String = ToastCorner.bottomRight.rawValue
    @AppStorage("AgentTAB.sounds.enabled") var soundsEnabled: Bool = true
    @AppStorage("AgentTAB.sounds.waitingReminder") var waitingReminder: Bool = true

    var body: some View {
        Form {
            Picker("Toast position", selection: $toastCorner) {
                Text("Top left").tag(ToastCorner.topLeft.rawValue)
                Text("Top right").tag(ToastCorner.topRight.rawValue)
                Text("Bottom left").tag(ToastCorner.bottomLeft.rawValue)
                Text("Bottom right").tag(ToastCorner.bottomRight.rawValue)
            }
            Toggle("Notification sounds", isOn: $soundsEnabled)
            Toggle("Waiting reminder every 30s", isOn: $waitingReminder)
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
