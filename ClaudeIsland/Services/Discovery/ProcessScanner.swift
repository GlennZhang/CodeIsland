//
//  ProcessScanner.swift
//  ClaudeIsland
//
//  Active process discovery for supported AI agents.
//

import Darwin
import Foundation
import os.log

private let processScannerLogger = Logger(subsystem: "com.codeisland", category: "Discovery")

struct ProcessScanner: Sendable {
    struct DiscoveredProcess: Sendable {
        let pid: Int
        let ppid: Int
        let command: String
        let tty: String?
        let agentType: AgentType
        let cwd: String?
        let terminalApp: String?
        let isInTmux: Bool

        func with(cwd: String? = nil, terminalApp: String? = nil, isInTmux: Bool? = nil) -> DiscoveredProcess {
            DiscoveredProcess(
                pid: pid,
                ppid: ppid,
                command: command,
                tty: tty,
                agentType: agentType,
                cwd: cwd ?? self.cwd,
                terminalApp: terminalApp ?? self.terminalApp,
                isInTmux: isInTmux ?? self.isInTmux
            )
        }
    }

    func scan() -> [DiscoveredProcess] {
        guard let output = ProcessExecutor.shared.runSyncOrNil(
            "/bin/ps",
            arguments: ["-eo", "pid,ppid,tty,state,command"]
        ) else {
            return []
        }

        var rows: [(pid: Int, ppid: Int, tty: String?, command: String, state: String, agent: any AgentDescriptor)] = []

        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(maxSplits: 4, omittingEmptySubsequences: true) { $0.isWhitespace }
                .map(String.init)

            guard parts.count >= 5,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { continue }

            let tty = parts[2] == "??" ? nil : parts[2]
            let state = parts[3]
            let command = parts[4]

            guard !state.contains("Z"),
                  let agent = agentForCommand(command) else { continue }

            rows.append((pid, ppid, tty, command, state, agent))
        }

        let agentPids = Set(rows.map(\.pid))
        processScannerLogger.debug("Scanned \(rows.count, privacy: .public) agent rows")

        return rows.compactMap { row in
            guard !agentPids.contains(row.ppid) else { return nil }
            return DiscoveredProcess(
                pid: row.pid,
                ppid: row.ppid,
                command: row.command,
                tty: row.tty,
                agentType: row.agent.type,
                cwd: nil,
                terminalApp: nil,
                isInTmux: false
            )
        }
    }

    func enrich(_ processes: [DiscoveredProcess]) -> [DiscoveredProcess] {
        let tree = ProcessTreeBuilder.shared.buildTree()
        return processes.map { process in
            let cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: process.pid)
            let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: process.pid, tree: tree)
            let terminalApp: String?
            if let termPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: process.pid, tree: tree),
               let termInfo = tree[termPid] {
                let command = URL(fileURLWithPath: termInfo.command).lastPathComponent
                terminalApp = TerminalAppRegistry.displayName(for: command)
            } else {
                terminalApp = nil
            }
            return process.with(cwd: cwd, terminalApp: terminalApp, isInTmux: isInTmux)
        }
    }

    static func isProcessAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private func agentForCommand(_ command: String) -> (any AgentDescriptor)? {
        let tokens = command.split { $0.isWhitespace }.map(String.init)
        for token in tokens {
            let basename = URL(fileURLWithPath: token).lastPathComponent
            guard let agent = AgentRegistry.shared.agentForProcess(basename) else { continue }

            if agent.type == .codex && tokens.contains("app-server") {
                return nil
            }

            return agent
        }
        return nil
    }

}
