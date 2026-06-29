import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible tab bar (classic-prefs style). Unlike the native
            // toolbar TabView, it never collapses into a ">>" overflow menu when
            // the window is narrow — every section is one click, always shown.
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon)
                                .font(.system(size: 17))
                                .frame(height: 20)
                            Text(t.title)
                                .font(.system(size: 11))
                        }
                        .frame(width: 92, height: 46)
                        .contentShape(Rectangle())
                        .foregroundStyle(tab == t ? Color.accentColor : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tab == t ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.bar)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 400)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general:       GeneralSettings()
        case .notifications: NotificationsSettings()
        case .sounds:        SoundsSettings()
        case .updates:       UpdatesSettings()
        case .advanced:      AdvancedSettings()
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, notifications, sounds, updates, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:       return "General"
        case .notifications: return "Notifications"
        case .sounds:        return "Sounds"
        case .updates:       return "Updates"
        case .advanced:      return "Advanced"
        }
    }
    var icon: String {
        switch self {
        case .general:       return "gear"
        case .notifications: return "bell"
        case .sounds:        return "speaker.wave.2.fill"
        case .updates:       return "arrow.triangle.2.circlepath"
        case .advanced:      return "wrench.and.screwdriver"
        }
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
            Toggle("Waiting reminder every 30s", isOn: $waitingReminder)
            Toggle("Waiting pulse", isOn: $waitingPulse)
        }
        .padding()
    }
}

struct SoundsSettings: View {
    @AppStorage("AgentTAB.sounds.enabled") private var soundsEnabled = true
    @AppStorage("AgentTAB.sounds.vol.master") private var master: Double = 1.0
    @AppStorage("AgentTAB.sounds.vol.start") private var startVol: Double = 0.5
    @AppStorage("AgentTAB.sounds.vol.finish") private var finishVol: Double = 1.0
    @AppStorage("AgentTAB.sounds.vol.finishElevated") private var elevatedVol: Double = 1.0
    @AppStorage("AgentTAB.sounds.vol.waiting") private var waitingVol: Double = 1.0
    @AppStorage("AgentTAB.sounds.vol.spin") private var spinVol: Double = 1.0

    var body: some View {
        Form {
            Toggle("Notification sounds", isOn: $soundsEnabled)
            Section("Output") {
                row("Master", $master, SoundFX.shot)
            }
            Section("Per-sound levels") {
                row("Work starts", $startVol, SoundFX.reload)
                row("Task finished", $finishVol, SoundFX.shot)
                row("High-priority finished", $elevatedVol, SoundFX.shotgun)
                row("Needs you", $waitingVol, SoundFX.waiting)
                row("Revolver flick", $spinVol, SoundFX.spin)
            }
            Text("▶ previews each sound at its current level — tune by ear. Sliders work even with sounds off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func row(_ label: String, _ value: Binding<Double>, _ voice: SoundFX.Voice) -> some View {
        HStack {
            Text(label).frame(width: 150, alignment: .leading)
            Slider(value: value, in: 0 ... 1)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            Button { SoundFX.preview(voice) } label: {
                Image(systemName: "play.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Preview")
        }
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
