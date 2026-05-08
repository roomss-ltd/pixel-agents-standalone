import SwiftUI

struct OnboardingView: View {
    @AppStorage("AgentTAB.onboarding.completed") var completed = false
    @State private var step = 0
    @State private var hookInstallError: String?
    @State private var probe = EnvironmentProbe.detect()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            if probe.isDropInCandidate && step == 0 {
                dropInWelcome
            } else {
                switch step {
                case 0: welcome
                case 1: hookConsent
                case 2: optionalLogin
                default: done
                }
            }
        }
        .frame(width: 480, height: 360)
        .padding(40)
    }

    private var dropInWelcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Activity.done)
            Text("Existing setup detected").font(.title)
            Text("AgentTAB found your existing Claude tab status integration. It will read live data without modifying anything on your machine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue in drop-in mode") {
                UserDefaults.standard.set(true, forKey: "AgentTAB.onboarding.completed")
                UserDefaults.standard.set(true, forKey: "AgentTAB.dropInMode")
                completed = true
                dismiss()
            }
            .controlSize(.large)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagonpath.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Activity.thinking)
            Text("Welcome to AgentTAB").font(.title)
            Text("Track every Claude Code session at a glance, right in your notch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { step = 1 }.controlSize(.large)
        }
    }

    private var hookConsent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to Claude Code").font(.headline)
            Text("AgentTAB monitors Claude by registering hooks in your existing config (~/.claude/settings.json). This lets it know when each session starts, uses a tool, or finishes — instantly.")
                .foregroundStyle(.secondary)
            Text("AgentTAB will only add its own hooks; existing user hooks are preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let err = hookInstallError {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Skip (JSONL only)") { step = 2 }
                Spacer()
                Button("Install hooks") {
                    do {
                        try HookInstaller.install()
                        step = 2
                    } catch {
                        hookInstallError = error.localizedDescription
                    }
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var optionalLogin: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open at login?").font(.headline)
            Text("AgentTAB can launch automatically when you log in.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Not now") { step = 3 }
                Spacer()
                Button("Yes, open at login") {
                    LoginItem.register()
                    step = 3
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Activity.done)
            Text("All set").font(.title)
            Text("AgentTAB is now tracking your Claude sessions.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                completed = true
                dismiss()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}
