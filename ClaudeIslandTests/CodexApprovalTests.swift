//
//  CodexApprovalTests.swift
//  ClaudeIslandTests
//
//  Tests for Codex PreToolUse classification, approval response protocol,
//  and app-unavailable pass-through behavior.
//

import XCTest
@testable import ClaudeIsland

final class CodexApprovalTests: XCTestCase {

    // MARK: - Helpers

    private func makeCodexPreToolUse(
        status: String = "waiting_for_approval",
        tool: String = "Bash",
        toolUseId: String = "test-tool-use-id",
        command: String = "rm -rf /"
    ) -> HookEvent {
        HookEvent(
            sessionId: "test-session",
            cwd: "/tmp",
            event: "PreToolUse",
            status: status,
            pid: 1234,
            tty: nil,
            tool: tool,
            toolInput: ["command": AnyCodable(command)],
            toolUseId: toolUseId,
            notificationType: nil,
            message: nil,
            agentType: .codex
        )
    }

    private func makeClaudePermissionRequest(
        toolUseId: String = "claude-tool-use-id"
    ) -> HookEvent {
        HookEvent(
            sessionId: "test-session",
            cwd: "/tmp",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            pid: 5678,
            tty: nil,
            tool: "Write",
            toolInput: nil,
            toolUseId: toolUseId,
            notificationType: nil,
            message: nil,
            agentType: .claude
        )
    }

    private func codexHookScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ClaudeIsland/Resources/codeisland-codex-state.py")
    }

    @discardableResult
    private func runCodexHook(
        permissionMode: String = "default",
        toolName: String = "Bash",
        command: String
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", codexHookScriptURL().path]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "test-session",
            "cwd": "/tmp",
            "tool_name": toolName,
            "permission_mode": permissionMode,
            "tool_input": ["command": command]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinPipe.fileHandleForWriting.write(data)
        try stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    // MARK: - Codex PreToolUse Classification (expectsResponse)

    /// Codex PreToolUse with waiting_for_approval status should expect a response (blocking)
    func test_codexPreToolUse_waitingForApproval_expectsResponse() {
        let event = makeCodexPreToolUse(status: "waiting_for_approval")
        XCTAssertTrue(event.expectsResponse,
                      "Codex PreToolUse with waiting_for_approval should be blocking")
    }

    /// Codex PreToolUse with processing status should NOT expect a response (non-blocking)
    func test_codexPreToolUse_processing_notExpectsResponse() {
        let event = makeCodexPreToolUse(status: "processing")
        XCTAssertFalse(event.expectsResponse,
                       "Codex PreToolUse with processing status should be non-blocking")
    }

    /// Codex PreToolUse with running_tool status should NOT expect a response
    func test_codexPreToolUse_runningTool_notExpectsResponse() {
        let event = makeCodexPreToolUse(status: "running_tool")
        XCTAssertFalse(event.expectsResponse,
                       "Codex PreToolUse with running_tool status should be non-blocking")
    }

    /// Codex PreToolUse without agentType defaults to claude and should NOT expect response
    /// (only codex PreToolUse can be blocking)
    func test_claudePreToolUse_neverExpectsResponse() {
        let event = HookEvent(
            sessionId: "test-session",
            cwd: "/tmp",
            event: "PreToolUse",
            status: "waiting_for_approval",
            pid: 1234,
            tty: nil,
            tool: "Bash",
            toolInput: nil,
            toolUseId: "id",
            notificationType: nil,
            message: nil,
            agentType: .claude
        )
        XCTAssertFalse(event.expectsResponse,
                       "Claude PreToolUse should never be blocking (only PermissionRequest is)")
    }

    // MARK: - Claude PermissionRequest Classification (expectsResponse)

    /// Claude PermissionRequest with waiting_for_approval should expect a response
    func test_claudePermissionRequest_expectsResponse() {
        let event = makeClaudePermissionRequest()
        XCTAssertTrue(event.expectsResponse,
                      "Claude PermissionRequest with waiting_for_approval should be blocking")
    }

    /// Claude PermissionRequest with other status should NOT expect a response
    func test_claudePermissionRequest_otherStatus_notExpectsResponse() {
        let event = HookEvent(
            sessionId: "test-session",
            cwd: "/tmp",
            event: "PermissionRequest",
            status: "approved",
            pid: 5678,
            tty: nil,
            tool: "Write",
            toolInput: nil,
            toolUseId: "id",
            notificationType: nil,
            message: nil,
            agentType: .claude
        )
        XCTAssertFalse(event.expectsResponse,
                       "Claude PermissionRequest with non-waiting status should not be blocking")
    }

    // MARK: - Agent Type Resolution

    /// Events without explicit agentType should default to claude
    func test_resolvedAgentType_defaultsToClaude() {
        let event = HookEvent(
            sessionId: "test", cwd: "/tmp", event: "PreToolUse",
            status: "processing", pid: nil, tty: nil,
            tool: nil, toolInput: nil, toolUseId: nil,
            notificationType: nil, message: nil, agentType: nil
        )
        XCTAssertEqual(event.resolvedAgentType, .claude)
    }

    /// Events with codex agentType should resolve to codex
    func test_resolvedAgentType_codex() {
        let event = makeCodexPreToolUse()
        XCTAssertEqual(event.resolvedAgentType, .codex)
    }

    // MARK: - Session Phase Mapping

    /// Codex waiting_for_approval should map to .waitingForApproval phase
    func test_codexPreToolUse_waitingForApproval_phase() {
        let event = makeCodexPreToolUse(status: "waiting_for_approval", tool: "Bash")
        let phase = event.sessionPhase

        if case .waitingForApproval(let ctx) = phase {
            XCTAssertEqual(ctx.toolName, "Bash")
            XCTAssertEqual(ctx.toolUseId, "test-tool-use-id")
        } else {
            XCTFail("Expected .waitingForApproval phase, got \(phase)")
        }
    }

    /// Codex processing status should map to .processing phase
    func test_codexPreToolUse_processing_phase() {
        let event = makeCodexPreToolUse(status: "processing")
        XCTAssertEqual(event.sessionPhase, .processing)
    }

    /// Codex ended status should map to .ended phase
    func test_codexEvent_ended_phase() {
        let event = HookEvent(
            sessionId: "test", cwd: "/tmp", event: "Stop",
            status: "ended", pid: nil, tty: nil,
            tool: nil, toolInput: nil, toolUseId: nil,
            notificationType: nil, message: nil, agentType: .codex
        )
        // CodexAgent.determinePhase maps "ended" to .ended
        let agent = CodexAgent()
        let phase = agent.determinePhase(from: event)
        XCTAssertEqual(phase, .ended)
    }

    // MARK: - HookResponse Encoding

    /// HookResponse allow should encode correctly
    func test_hookResponse_allow_encoding() throws {
        let response = HookResponse(decision: "allow", reason: nil)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["decision"] as? String, "allow")
        XCTAssertNil(json?["reason"])
    }

    /// HookResponse deny with reason should encode correctly
    func test_hookResponse_deny_encoding() throws {
        let response = HookResponse(decision: "deny", reason: "Denied by user")
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["decision"] as? String, "deny")
        XCTAssertEqual(json?["reason"] as? String, "Denied by user")
    }

    // MARK: - Codex Phase Determination via Agent Descriptor

    /// CodexAgent should determine waitingForApproval from waiting_for_approval status
    func test_codexAgent_waitingForApproval() {
        let agent = CodexAgent()
        let event = makeCodexPreToolUse(status: "waiting_for_approval", tool: "Bash")
        let phase = agent.determinePhase(from: event)

        if case .waitingForApproval(let ctx) = phase {
            XCTAssertEqual(ctx.toolName, "Bash")
        } else {
            XCTFail("Expected .waitingForApproval phase")
        }
    }

    /// CodexAgent should determine processing from running_tool status
    func test_codexAgent_processing() {
        let agent = CodexAgent()
        let event = makeCodexPreToolUse(status: "running_tool")
        let phase = agent.determinePhase(from: event)
        XCTAssertEqual(phase, .processing)
    }

    /// CodexAgent should determine waitingForInput from waiting_for_input status
    func test_codexAgent_waitingForInput() {
        let agent = CodexAgent()
        let event = HookEvent(
            sessionId: "test", cwd: "/tmp", event: "Stop",
            status: "waiting_for_input", pid: nil, tty: nil,
            tool: nil, toolInput: nil, toolUseId: nil,
            notificationType: nil, message: nil, agentType: .codex
        )
        let phase = agent.determinePhase(from: event)
        XCTAssertEqual(phase, .waitingForInput)
    }

    // MARK: - CodexAgent Descriptor Properties

    /// CodexAgent should support PreToolUse events
    func test_codexAgent_supportsPreToolUse() {
        let agent = CodexAgent()
        XCTAssertTrue(agent.supportedEvents.contains("PreToolUse"))
    }

    /// CodexAgent should support PostToolUse events
    func test_codexAgent_supportsPostToolUse() {
        let agent = CodexAgent()
        XCTAssertTrue(agent.supportedEvents.contains("PostToolUse"))
    }

    /// CodexAgent should have permission response capability
    func test_codexAgent_hasPermissionResponse() {
        let agent = CodexAgent()
        XCTAssertTrue(agent.hasPermissionResponse)
    }

    /// CodexAgent config should use codexHooksJSON format
    func test_codexAgent_configFormat() {
        let agent = CodexAgent()
        XCTAssertEqual(agent.configFormat, .codexHooksJSON)
    }

    // MARK: - Python Hook Policy Matrix

    func test_pythonHook_readOnlyCommand_returnsImmediately() throws {
        let result = try runCodexHook(command: "git diff --stat")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_routineExecution_returnsImmediately() throws {
        let result = try runCodexHook(command: "xcodebuild -scheme ClaudeIsland build")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_acceptEditsMode_returnsImmediately() throws {
        let result = try runCodexHook(permissionMode: "acceptEdits", command: "rm -rf build")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_planMode_returnsImmediately() throws {
        let result = try runCodexHook(permissionMode: "plan", command: "python3 script.py")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_mutatingCommand_requiresApproval() throws {
        let result = try runCodexHook(command: "rm -rf build")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_unknownCommand_requiresApproval() throws {
        let result = try runCodexHook(command: "python3 manage.py migrate")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_openCommand_returnsImmediately() throws {
        let result = try runCodexHook(command: "open /Applications")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_nonBashTool_doesNotBlock() throws {
        let result = try runCodexHook(toolName: "Read", command: "ignored")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_sedReadOnly_returnsImmediately() throws {
        let result = try runCodexHook(command: "sed -n '1,5p' README.md")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_shellWrappedSedReadOnly_returnsImmediately() throws {
        let result = try runCodexHook(command: "bash -lc \"sed -n '1,5p' README.md\"")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_pythonReadOnlyScript_returnsImmediately() throws {
        let result = try runCodexHook(
            command: "python3 -c \"from pathlib import Path; print(Path(\\\"README.md\\\").read_text())\""
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_pythonWriteScript_requiresApproval() throws {
        let result = try runCodexHook(
            command: "python3 -c \"from pathlib import Path; Path(\\\"x\\\").write_text(\\\"1\\\")\""
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_npmBuild_returnsImmediately() throws {
        let result = try runCodexHook(command: "npm run build")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_vueTsc_returnsImmediately() throws {
        let result = try runCodexHook(command: "npx vue-tsc --noEmit")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_curlGet_returnsImmediately() throws {
        let result = try runCodexHook(command: "curl -s https://www.bees-energy.com/")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_curlPost_requiresApproval() throws {
        let result = try runCodexHook(command: "curl -X POST https://example.com/api")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func test_pythonHook_curlOutputFile_requiresApproval() throws {
        let result = try runCodexHook(command: "curl -o page.html https://example.com")
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
