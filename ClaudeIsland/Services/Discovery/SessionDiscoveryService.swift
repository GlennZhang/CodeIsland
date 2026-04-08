//
//  SessionDiscoveryService.swift
//  ClaudeIsland
//
//  Periodically scans for supported AI agent processes.
//

import Foundation
import os.log

private let discoveryLogger = Logger(subsystem: "com.codeisland", category: "Discovery")

actor SessionDiscoveryService {
    static let shared = SessionDiscoveryService()

    private let scanIntervalNs: UInt64 = 10_000_000_000
    private let scanner = ProcessScanner()
    private var discoveredPIDs: Set<Int> = []
    private var scanTask: Task<Void, Never>?
    private var activityToken: NSObjectProtocol?

    func start() async {
        guard scanTask == nil else { return }

        activityToken = Foundation.ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Vibe Island session discovery"
        )

        let interval = scanIntervalNs
        scanTask = Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                await performScan()
            }
        }

        await performScan()
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil

        if let activityToken {
            Foundation.ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    func scanNow() async {
        await performScan()
    }

    private func performScan() async {
        let scanned = scanner.scan()
        let currentPIDs = Set(scanned.map(\.pid))
        let newPIDs = currentPIDs.subtracting(discoveredPIDs)
        let terminatedPIDs = discoveredPIDs.subtracting(currentPIDs)

        discoveryLogger.debug("Scan current=\(currentPIDs.count, privacy: .public) new=\(newPIDs.count, privacy: .public) terminated=\(terminatedPIDs.count, privacy: .public)")

        let newProcesses = scanner.enrich(scanned.filter { newPIDs.contains($0.pid) })

        for process in newProcesses {
            await SessionStore.shared.process(.processDiscovered(
                pid: process.pid,
                agentType: process.agentType,
                cwd: process.cwd,
                tty: process.tty,
                terminalApp: process.terminalApp,
                isInTmux: process.isInTmux
            ))
        }

        for pid in terminatedPIDs {
            await SessionStore.shared.process(.processTerminated(pid: pid))
        }

        discoveredPIDs = currentPIDs
    }
}
