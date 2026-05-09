import Foundation

enum HookInstaller {
    static let supportDir: URL = {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentTAB")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var hookScriptPath: URL { supportDir.appendingPathComponent("hook.sh") }
    static var socketPath: String { supportDir.appendingPathComponent("hook.sock").path }
    static var installedHooksManifest: URL { supportDir.appendingPathComponent("installed-hooks.json") }

    static var hooksInstalled: Bool {
        FileManager.default.fileExists(atPath: installedHooksManifest.path)
    }

    static var claudeSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static let hookEvents = [
        "PreToolUse", "PostToolUse", "UserPromptSubmit", "PermissionRequest",
        "Stop", "SubagentStop", "SessionStart", "SessionEnd",
    ]

    static func install() throws {
        // 1. Copy hook.sh from bundle to support dir
        guard let bundleHook = Bundle.main.url(forResource: "hook", withExtension: "sh") else {
            throw NSError(domain: "AgentTAB", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "hook.sh missing from bundle"])
        }
        if FileManager.default.fileExists(atPath: hookScriptPath.path) {
            try FileManager.default.removeItem(at: hookScriptPath)
        }
        try FileManager.default.copyItem(at: bundleHook, to: hookScriptPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath.path)

        // 2. Read existing settings.json
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeSettingsPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = obj
        }

        // 3. Merge our hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let installedNow = Date().timeIntervalSince1970
        var manifest: [String: [String]] = [:]

        // Claude Code passes each hook command to `/bin/sh -c`, which word-splits
        // on whitespace. The hook lives under `~/Library/Application Support/...`
        // (a path with a space), so we must single-quote it before serialising.
        let quotedCommand = "'\(hookScriptPath.path)'"
        for event in hookEvents {
            var existing = hooks[event] as? [[String: Any]] ?? []
            let cmd: [String: Any] = [
                "hooks": [["type": "command", "command": quotedCommand]]
            ]
            existing.append(cmd)
            hooks[event] = existing
            manifest[event] = [quotedCommand]
        }
        settings["hooks"] = hooks

        // 4. Atomic write
        let tmpURL = claudeSettingsPath.appendingPathExtension("tmp")
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: tmpURL)
        // Ensure parent .claude/ exists
        try FileManager.default.createDirectory(at: claudeSettingsPath.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: claudeSettingsPath.path) {
            _ = try FileManager.default.replaceItemAt(claudeSettingsPath, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: claudeSettingsPath)
        }

        // 5. Write manifest
        let manifestData = try JSONSerialization.data(
            withJSONObject: ["installed_at": installedNow, "hooks": manifest],
            options: .prettyPrinted
        )
        try manifestData.write(to: installedHooksManifest)
    }

    static func uninstall() throws {
        guard let manifestData = try? Data(contentsOf: installedHooksManifest),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let installedHooks = manifest["hooks"] as? [String: [String]],
              let settingsData = try? Data(contentsOf: claudeSettingsPath),
              var settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        else { return }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, paths) in installedHooks {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
                return nested.contains { ($0["command"] as? String).map(paths.contains) ?? false }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        let tmpURL = claudeSettingsPath.appendingPathExtension("tmp")
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: tmpURL)
        _ = try FileManager.default.replaceItemAt(claudeSettingsPath, withItemAt: tmpURL)

        try? FileManager.default.removeItem(at: installedHooksManifest)
        try? FileManager.default.removeItem(at: hookScriptPath)
    }
}
