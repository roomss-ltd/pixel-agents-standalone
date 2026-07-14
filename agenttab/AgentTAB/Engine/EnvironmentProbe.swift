// agenttab/AgentTAB/Engine/EnvironmentProbe.swift
import Foundation

struct EnvironmentProbe {
    let zellijState: ZellijState
    let pluginState: PluginState
    let hookState: HookState

    enum ZellijState { case notInstalled, installed, running }
    enum PluginState { case none, configured, producingStatusFiles }
    enum HookState { case none, legacyClaudeTabStatus, agentTAB, mixed }

    static func detect(
        statusDir: URL = ZellijStatusReader.defaultStatusDir
    ) -> EnvironmentProbe {
        return EnvironmentProbe(
            zellijState: detectZellij(),
            pluginState: detectPlugin(statusDir: statusDir),
            hookState: detectHooks()
        )
    }

    private static func detectZellij() -> ZellijState {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["zellij"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .notInstalled }

        let psProcess = Process()
        psProcess.launchPath = "/bin/sh"
        psProcess.arguments = ["-c", "pgrep -x zellij"]
        psProcess.standardOutput = Pipe()
        psProcess.standardError = Pipe()
        try? psProcess.run()
        psProcess.waitUntilExit()
        return psProcess.terminationStatus == 0 ? .running : .installed
    }

    private static func detectPlugin(statusDir: URL) -> PluginState {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/zellij/config.kdl")
        let configured = (try? String(contentsOf: configPath))?
            .contains("claude-tab-status.wasm") ?? false

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: [.contentModificationDateKey]),
              !files.isEmpty else {
            return configured ? .configured : .none
        }
        let recentlyWritten = files.contains { url in
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return Date().timeIntervalSince(mtime) < 60
        }
        return recentlyWritten ? .producingStatusFiles : .configured
    }

    private static func detectHooks() -> HookState {
        let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: claudeSettings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any]
        else { return .none }

        let allHookCommands = hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String }

        let hasAgentTAB = allHookCommands.contains { $0.contains("/AgentTAB/hook.sh") }
        let hasLegacy = allHookCommands.contains { $0.contains("claude-zj-hook.sh") }

        switch (hasAgentTAB, hasLegacy) {
        case (true, true):   return .mixed
        case (true, false):  return .agentTAB
        case (false, true):  return .legacyClaudeTabStatus
        case (false, false): return .none
        }
    }
}

extension EnvironmentProbe {
    /// Drop-in mode: existing setup detected, AgentTAB should not modify the environment.
    var isDropInCandidate: Bool {
        return zellijState == .running &&
               pluginState == .producingStatusFiles &&
               hookState != .none
    }
}
