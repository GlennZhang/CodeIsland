//
//  SessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class SessionMonitor: ObservableObject {
    private static let conversationParseRetryCooldown: TimeInterval = 30

    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()
    private var conversationParseInFlight = Set<String>()
    private var nextConversationParseAttempt: [String: Date] = [:]
    private var stalePermissionCleanupInFlight = Set<String>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.resolvedAgentType == .claude && event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd,
                            agentType: event.resolvedAgentType
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
        Task { await SessionStore.shared.startZombieScan() }

        Task {
            await SessionDiscoveryService.shared.start()
        }
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        Task { await SessionStore.shared.stopZombieScan() }
        Task {
            await SessionDiscoveryService.shared.stop()
        }
    }

    /// Remove all ended sessions from the store
    func clearEndedSessions() {
        Task { await SessionStore.shared.process(.clearEndedSessions) }
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            // Try the given sessionId first; if not found, search all sessions
            // for one with a pending permission (handles reconciliation ID changes)
            var session = await SessionStore.shared.session(for: sessionId)
            if session == nil {
                DebugLogger.log("Approval", "Session \(sessionId.prefix(8)) not found, searching all sessions")
                session = await SessionStore.shared.findSessionWithPendingPermission()
            }
            guard let session else {
                DebugLogger.log("Approval", "No session with pending permission found")
                return
            }
            guard let permission = session.activePermission else {
                DebugLogger.log("Approval", "No activePermission for \(session.sessionId.prefix(8)) phase=\(session.phase)")
                return
            }

            guard HookSocketServer.shared.hasPendingPermission(toolUseId: permission.toolUseId) else {
                DebugLogger.log("Approval", "No pending socket for tool \(permission.toolUseId.prefix(12)) — marking failed")
                await SessionStore.shared.process(
                    .permissionSocketFailed(sessionId: session.sessionId, toolUseId: permission.toolUseId)
                )
                return
            }

            DebugLogger.log("Approval", "Sending allow for \(session.sessionId.prefix(8)) tool=\(permission.toolUseId.prefix(12))")
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: session.sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            var session = await SessionStore.shared.session(for: sessionId)
            if session == nil {
                session = await SessionStore.shared.findSessionWithPendingPermission()
            }
            guard let session else { return }
            guard let permission = session.activePermission else {
                return
            }

            guard HookSocketServer.shared.hasPendingPermission(toolUseId: permission.toolUseId) else {
                await SessionStore.shared.process(
                    .permissionSocketFailed(sessionId: session.sessionId, toolUseId: permission.toolUseId)
                )
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: session.sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    // MARK: - Question Handling

    func skipQuestion(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let questionCtx = session.phase.questionContext else {
                return
            }

            await SessionStore.shared.process(
                .questionSkipped(sessionId: sessionId, toolUseId: questionCtx.toolUseId)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.archiveSession(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }

        let currentSessionIds = Set(sessions.map(\.sessionId))
        conversationParseInFlight = conversationParseInFlight.filter { currentSessionIds.contains($0) }
        nextConversationParseAttempt = nextConversationParseAttempt.filter { currentSessionIds.contains($0.key) }
        let currentPermissionToolIds = Set<String>(
            sessions.compactMap { session in
                guard session.supportsPermissionResponse else { return nil }
                return session.activePermission?.toolUseId
            }
        )
        stalePermissionCleanupInFlight = stalePermissionCleanupInFlight.filter { currentPermissionToolIds.contains($0) }

        for session in sessions {
            guard let permission = session.activePermission,
                  session.supportsPermissionResponse else {
                if let toolUseId = session.activePermission?.toolUseId {
                    stalePermissionCleanupInFlight.remove(toolUseId)
                }
                continue
            }

            let hasPending = HookSocketServer.shared.hasPendingPermission(toolUseId: permission.toolUseId)
            guard !hasPending else {
                stalePermissionCleanupInFlight.remove(permission.toolUseId)
                continue
            }
            guard stalePermissionCleanupInFlight.insert(permission.toolUseId).inserted else { continue }

            Task {
                await SessionStore.shared.process(
                    .permissionSocketFailed(sessionId: session.sessionId, toolUseId: permission.toolUseId)
                )
                await MainActor.run {
                    self.stalePermissionCleanupInFlight.remove(permission.toolUseId)
                }
            }
        }

        for session in sessions where shouldScheduleConversationInfoParse(for: session) {
            scheduleConversationInfoParse(for: session)
        }
    }

    private func shouldScheduleConversationInfoParse(for session: SessionState) -> Bool {
        guard session.agentType == .claude || session.agentType == .codex,
              !session.isDiscovered,
              !session.isArchivedForDefaultList,
              session.conversationInfo.firstUserMessage == nil,
              !conversationParseInFlight.contains(session.sessionId) else {
            return false
        }

        if let retryAfter = nextConversationParseAttempt[session.sessionId],
           retryAfter > Date() {
            return false
        }

        return true
    }

    private func scheduleConversationInfoParse(for session: SessionState) {
        let sessionId = session.sessionId
        let cwd = session.cwd
        conversationParseInFlight.insert(sessionId)

        Task { [weak self] in
            let info: ConversationInfo
            if session.agentType == .codex {
                info = await CodexConversationParser.shared.parse(
                    sessionId: sessionId,
                    cwd: cwd
                )
            } else {
                info = await ConversationParser.shared.parse(
                    sessionId: sessionId,
                    cwd: cwd
                )
            }

            await MainActor.run {
                guard let self else { return }
                self.conversationParseInFlight.remove(sessionId)
                if info.firstUserMessage != nil {
                    self.nextConversationParseAttempt.removeValue(forKey: sessionId)
                } else {
                    self.nextConversationParseAttempt[sessionId] = Date()
                        .addingTimeInterval(Self.conversationParseRetryCooldown)
                }
            }

            if info.firstUserMessage != nil {
                await SessionStore.shared.updateConversationInfo(
                    sessionId: sessionId,
                    info: info
                )
            }
        }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension SessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
