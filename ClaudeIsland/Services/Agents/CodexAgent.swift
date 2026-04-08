//
//  CodexAgent.swift
//  ClaudeIsland
//

import Foundation

struct CodexAgent: AgentDescriptor {
    let type = AgentType.codex
    let displayName = "Codex CLI"
    let processNames: Set<String> = ["codex"]
    let configFilePath = NSHomeDirectory() + "/.codex/config.toml"
    let configFormat = ConfigFormat.codexHooksJSON
    let hookScriptResourceName = "codeisland-codex-state"
    let supportedEvents: Set<String> = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "SessionStart", "Stop"
    ]
    let hasPermissionResponse = true

    func determinePhase(from event: HookEvent) -> SessionPhase? {
        switch event.status {
        case "waiting_for_approval":
            return .waitingForApproval(PermissionContext(
                toolUseId: event.toolUseId ?? "",
                toolName: event.tool ?? "Bash",
                toolInput: event.toolInput,
                receivedAt: Date()
            ))
        case "running_tool", "processing", "starting":
            return .processing
        case "waiting_for_input":
            return .waitingForInput
        case "ended":
            return .ended
        default:
            return .idle
        }
    }
}
