//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation

struct HookInstaller {
    enum InstallState: Equatable {
        case installed
        case missing
        case unavailable
    }

    /// Install hook scripts and update per-agent configuration on app launch.
    static func installIfNeeded() {
        cleanupLegacyHooks()
        installAll()
    }

    static func installAll() {
        for agent in AgentRegistry.shared.allAgents {
            install(agent: agent)
        }
    }

    static func install(agent: any AgentDescriptor) {
        switch agent.type {
        case .claude:
            installClaude(agent: agent)
        case .codex:
            guard isAgentAvailable(agent) else { return }
            installCodex(agent: agent)
        case .gemini, .cursor, .opencode, .unknown:
            break
        }
    }

    private static func installClaude(agent: any AgentDescriptor) {

        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-state.py")
        let bridgeScript = hooksDir.appendingPathComponent("codeisland-bridge")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: agent.hookScriptResourceName, withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        if let bundledBridge = Bundle.main.url(forResource: "codeisland-bridge", withExtension: nil) {
            try? FileManager.default.removeItem(at: bridgeScript)
            try? FileManager.default.copyItem(at: bundledBridge, to: bridgeScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bridgeScript.path
            )
        }

        updateSettings(at: settings)
    }

    private static func installCodex(agent: any AgentDescriptor) {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let hooksDir = codexDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-codex-state.py")
        let bridgeScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/codeisland-bridge")
        let config = codexDir.appendingPathComponent("config.toml")
        let hooks = codexDir.appendingPathComponent("hooks.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: agent.hookScriptResourceName, withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        if let bundledBridge = Bundle.main.url(forResource: "codeisland-bridge", withExtension: nil) {
            try? FileManager.default.createDirectory(
                at: bridgeScript.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: bridgeScript)
            try? FileManager.default.copyItem(at: bundledBridge, to: bridgeScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bridgeScript.path
            )
        }

        updateCodexConfig(at: config)
        updateCodexHooks(at: hooks)
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) ~/.claude/hooks/codeisland-state.py"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("codeisland-state.py")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        writeJSON(json, to: settingsURL)
    }

    private static func updateCodexConfig(at configURL: URL) {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = enableCodexHooks(in: existing)
        guard updated != existing else { return }
        backupIfNeeded(configURL)
        try? updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func enableCodexHooks(in toml: String) -> String {
        var lines = toml.components(separatedBy: .newlines)

        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            let sectionEnd = lines[(featuresIndex + 1)...].firstIndex { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            } ?? lines.endIndex

            if let flagIndex = lines[(featuresIndex + 1)..<sectionEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("codex_hooks")
            }) {
                lines[flagIndex] = "codex_hooks = true"
            } else {
                lines.insert("codex_hooks = true", at: sectionEnd)
            }
        } else {
            if !lines.isEmpty && lines.last != "" {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("codex_hooks = true")
        }

        let updated = lines.joined(separator: "\n")
        return updated.hasSuffix("\n") ? updated : updated + "\n"
    }

    private static func updateCodexHooks(at hooksURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let command = codexHookCommand()
        let defaultHookEntry: [[String: Any]] = [["type": "command", "command": command, "timeout": 10]]
        let blockingHookEntry: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withoutMatcher: [[String: Any]] = [["hooks": defaultHookEntry]]
        let withoutMatcherBlocking: [[String: Any]] = [["hooks": blockingHookEntry]]
        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withoutMatcherBlocking),
            ("PostToolUse", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("Stop", withoutMatcher),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                existingEvent = upsertingScriptHook(
                    in: existingEvent,
                    scriptName: nil,
                    replacement: config
                )
                hooks[event] = existingEvent
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks
        writeJSON(json, to: hooksURL)
    }

    private static func upsertingScriptHook(
        in entries: [[String: Any]],
        scriptName: String?,
        replacement: [[String: Any]]
    ) -> [[String: Any]] {
        var updated = entries.filter { entry in
            !entryContainsManagedHook(entry, scriptName: scriptName)
        }
        updated.append(contentsOf: replacement)
        return updated
    }

    private static func hasScriptHook(_ entries: [[String: Any]], scriptName: String) -> Bool {
        entries.contains { entry in
            entryContainsManagedHook(entry, scriptName: scriptName)
        }
    }

    private static func entryContainsManagedHook(_ entry: [String: Any], scriptName: String?) -> Bool {
        if let entryHooks = entry["hooks"] as? [[String: Any]] {
            return entryHooks.contains { h in
                let cmd = h["command"] as? String ?? ""
                return isManagedCodexHookCommand(cmd, scriptName: scriptName)
            }
        }
        return false
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let existingData = try? Data(contentsOf: url)
        if existingData == data { return }

        backupIfNeeded(url)
        try? data.write(to: url)
    }

    private static func backupIfNeeded(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".codeisland.bak")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: url, to: backupURL)
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        isInstalled(agentType: .claude)
    }

    static func isInstalled(agentType: AgentType) -> Bool {
        switch agentType {
        case .claude:
            return isClaudeInstalled()
        case .codex:
            return isCodexInstalled()
        case .gemini, .cursor, .opencode, .unknown:
            return false
        }
    }

    static func installState(for agent: any AgentDescriptor) -> InstallState {
        guard isAgentAvailable(agent) else { return .unavailable }
        return isInstalled(agentType: agent.type) ? .installed : .missing
    }

    private static func isClaudeInstalled() -> Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settings = claudeDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("codeisland-state.py") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private static func isCodexInstalled() -> Bool {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let config = codexDir.appendingPathComponent("config.toml")
        let hooksURL = codexDir.appendingPathComponent("hooks.json")

        let configText = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        guard configText.components(separatedBy: .newlines).contains(where: {
            $0.trimmingCharacters(in: .whitespaces) == "codex_hooks = true"
        }) else { return false }

        guard let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]],
               entries.contains(where: { entryContainsManagedHook($0, scriptName: nil) }) {
                return true
            }
        }
        return false
    }

    private static func codexHookCommand() -> String {
        if let bridge = detectCodexBridgePath() {
            return quoteIfNeeded(bridge) + " --source codex"
        }

        let python = detectPython()
        return "\(python) ~/.codex/hooks/codeisland-codex-state.py"
    }

    private static func detectCodexBridgePath() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/.claude/hooks/codeisland-bridge",
            "/Applications/CodeIsland.app/Contents/Helpers/codeisland-bridge",
            home + "/Applications/CodeIsland.app/Contents/Helpers/codeisland-bridge",
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func isManagedCodexHookCommand(_ command: String, scriptName: String?) -> Bool {
        if let scriptName, !scriptName.isEmpty {
            return command.contains(scriptName)
        }

        return command.contains("codeisland-codex-state.py")
            || command.contains("codeisland-bridge")
    }

    private static func quoteIfNeeded(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("codeisland-state.py")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    /// Script basenames left behind by older app versions (Claude Island,
    /// Code Island) that should no longer be referenced in settings.json.
    static let legacyHookScripts = ["claude-island-state.py"]

    /// Strip hook entries from older app versions and delete their leftover
    /// scripts. Idempotent — safe to run every launch.
    static func cleanupLegacyHooks() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let settings = claudeDir.appendingPathComponent("settings.json")

        // 1. Delete legacy script files on disk (no-op if missing).
        for name in legacyHookScripts {
            let path = hooksDir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: path)
        }

        // 2. Prune legacy entries from settings.json (pure function below).
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let pruned = pruneLegacyHookEntries(from: json, legacyScripts: legacyHookScripts)
        guard pruned.changed else { return }

        guard let newData = try? JSONSerialization.data(
            withJSONObject: pruned.result,
            options: [.prettyPrinted, .sortedKeys]
        ), !newData.isEmpty,
              // Round-trip check: serialize → deserialize must succeed before we write.
              (try? JSONSerialization.jsonObject(with: newData)) != nil else {
            return
        }
        try? newData.write(to: settings, options: .atomic)
    }

    /// Pure function: given a decoded settings.json dict, return a copy with
    /// every hook group that references any legacy script removed. Empty
    /// hook events are dropped; if the entire `hooks` map ends up empty the
    /// `hooks` key itself is removed. `changed` is true iff at least one
    /// entry was pruned.
    ///
    /// Kept `internal` so future tests can `@testable import` this directly
    /// without touching the file system.
    static func pruneLegacyHookEntries(
        from json: [String: Any],
        legacyScripts: [String]
    ) -> (result: [String: Any], changed: Bool) {
        guard var hooks = json["hooks"] as? [String: Any] else {
            return (json, false)
        }

        func entryReferencesLegacy(_ entry: [String: Any]) -> Bool {
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return legacyScripts.contains { cmd.contains($0) }
            }
        }

        var changed = false
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            let before = entries.count
            entries.removeAll(where: entryReferencesLegacy)
            guard entries.count != before else { continue }
            changed = true
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        guard changed else { return (json, false) }

        var result = json
        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return (result, true)
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    private static func isAgentAvailable(_ agent: any AgentDescriptor) -> Bool {
        switch agent.type {
        case .codex:
            return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex") ||
                commandExists(agent.processNames.first ?? "")
        case .claude:
            return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude") ||
                commandExists(agent.processNames.first ?? "")
        case .gemini, .cursor, .opencode, .unknown:
            return false
        }
    }

    private static func commandExists(_ command: String) -> Bool {
        guard !command.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
