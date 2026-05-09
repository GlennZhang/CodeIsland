//
//  TerminalWriterRoutingTests.swift
//  ClaudeIslandTests
//

import XCTest
@testable import ClaudeIsland

final class TerminalWriterRoutingTests: XCTestCase {

    func test_cmuxWinsOverExplicitCodexTerminalHint() {
        let backend = TerminalWriter.preferredTerminalBackend(
            terminalApp: "Codex",
            hasCmuxTarget: true,
            detectedFallback: "ghostty"
        )

        XCTAssertEqual(backend, "cmux")
    }

    func test_explicitTerminalHintUsedWhenNoCmuxTarget() {
        let backend = TerminalWriter.preferredTerminalBackend(
            terminalApp: "Ghostty",
            hasCmuxTarget: false,
            detectedFallback: "terminal"
        )

        XCTAssertEqual(backend, "ghostty")
    }

    func test_detectedFallbackUsedWhenNoHintOrCmuxTarget() {
        let backend = TerminalWriter.preferredTerminalBackend(
            terminalApp: nil,
            hasCmuxTarget: false,
            detectedFallback: "iterm2"
        )

        XCTAssertEqual(backend, "iterm2")
    }

    func test_codexCmuxSubmissionUsesSeparateEnterKey() {
        let plan = TerminalWriter.cmuxSubmissionPlan(
            text: "OK",
            terminalApp: "Codex",
            hasSurfaceTarget: true
        )

        XCTAssertEqual(plan, .sendThenKey(text: "OK", key: "enter"))
    }

    func test_standardCmuxSubmissionAppendsReturnInline() {
        let plan = TerminalWriter.cmuxSubmissionPlan(
            text: "OK",
            terminalApp: "Ghostty",
            hasSurfaceTarget: true
        )

        XCTAssertEqual(plan, .appendReturn("OK\r"))
    }

    func test_codexFallsBackToInlineReturnWithoutSurface() {
        let plan = TerminalWriter.cmuxSubmissionPlan(
            text: "OK",
            terminalApp: "Codex",
            hasSurfaceTarget: false
        )

        XCTAssertEqual(plan, .appendReturn("OK\r"))
    }
}
