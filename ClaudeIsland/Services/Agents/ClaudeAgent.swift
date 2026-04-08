//
//  ClaudeAgent.swift
//  ClaudeIsland
//

import Foundation

struct ClaudeAgent: AgentDescriptor {
    let type = AgentType.claude
    let displayName = "Claude Code"
    let processNames: Set<String> = ["claude"]
    let configFilePath = NSHomeDirectory() + "/.claude/settings.json"
    let configFormat = ConfigFormat.json
    let hookScriptResourceName = "codeisland-state"
    let supportedEvents: Set<String> = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Notification", "Stop",
        "SubagentStop", "SessionStart", "SessionEnd", "PreCompact"
    ]
    let hasPermissionResponse = true

    func determinePhase(from event: HookEvent) -> SessionPhase? {
        event.determinePhase()
    }
}
