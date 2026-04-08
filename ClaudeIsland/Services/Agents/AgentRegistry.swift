//
//  AgentRegistry.swift
//  ClaudeIsland
//

import Foundation

struct AgentRegistry: Sendable {
    static let shared = AgentRegistry(agents: [
        ClaudeAgent(),
        CodexAgent()
    ])

    private let agents: [AgentType: any AgentDescriptor]

    init(agents descriptors: [any AgentDescriptor]) {
        var table: [AgentType: any AgentDescriptor] = [:]
        for descriptor in descriptors {
            table[descriptor.type] = descriptor
        }
        self.agents = table
    }

    var allAgents: [any AgentDescriptor] {
        AgentType.allCases.compactMap { agents[$0] }
    }

    var allProcessNames: Set<String> {
        Set(allAgents.flatMap(\.processNames))
    }

    var installedAgents: [any AgentDescriptor] {
        allAgents.filter { agent in
            switch agent.type {
            case .codex:
                return commandExists(agent.processNames.first ?? "") ||
                    FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex")
            default:
                return FileManager.default.fileExists(atPath: agent.configFilePath)
            }
        }
    }

    func agent(for type: AgentType) -> (any AgentDescriptor)? {
        agents[type]
    }

    func agentForProcess(_ processName: String) -> (any AgentDescriptor)? {
        let basename = URL(fileURLWithPath: processName).lastPathComponent
        return allAgents.first { $0.processNames.contains(basename) }
    }

    private func commandExists(_ command: String) -> Bool {
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
