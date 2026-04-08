//
//  AgentType.swift
//  ClaudeIsland
//
//  Agent descriptors for multi-agent session discovery and hook handling.
//

import Foundation
import SwiftUI

enum AgentType: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
    case gemini
    case cursor
    case opencode
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AgentType(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor Agent"
        case .opencode: return "OpenCode"
        case .unknown: return "Unknown Agent"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        case .unknown: return "Unknown"
        }
    }

    var compactAbbreviation: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .gemini: return "G"
        case .cursor: return "R"
        case .opencode: return "O"
        case .unknown: return "?"
        }
    }

    var tagColor: Color {
        switch self {
        case .claude: return Color(red: 0.38, green: 0.65, blue: 0.98)
        case .codex: return Color(red: 0.13, green: 0.75, blue: 0.45)
        case .gemini: return Color(red: 0.40, green: 0.60, blue: 1.00)
        case .cursor: return Color(red: 0.40, green: 0.91, blue: 0.98)
        case .opencode: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .unknown: return Color.gray
        }
    }
}

enum ConfigFormat: String, Codable, Sendable {
    case json
    case toml
    case codexHooksJSON
    case jsonc
}

protocol AgentDescriptor: Sendable {
    var type: AgentType { get }
    var displayName: String { get }
    var processNames: Set<String> { get }
    var configFilePath: String { get }
    var configFormat: ConfigFormat { get }
    var hookScriptResourceName: String { get }
    var supportedEvents: Set<String> { get }
    var hasPermissionResponse: Bool { get }

    func determinePhase(from event: HookEvent) -> SessionPhase?
}
