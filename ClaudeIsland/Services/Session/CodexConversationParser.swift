//
//  CodexConversationParser.swift
//  ClaudeIsland
//
//  Parses Codex CLI JSONL session files (~/.codex/sessions/**/*.jsonl).
//  Maps Codex's rollout format to the same ChatMessage/ChatHistoryItem models
//  used by the Claude parser, enabling unified display in the chat view.
//

import Foundation
import os.log

/// Parses Codex CLI JSONL session files
actor CodexConversationParser {
    static let shared = CodexConversationParser()

    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "CodexParser")

    // MARK: - State

    private var incrementalState: [String: IncrementalState] = [:]
    private var indexPathCache: IndexCache?

    private struct IndexCache {
        let entries: [IndexEntry]
        let loadedAt: Date
    }

    /// Entry from session_index.jsonl
    private struct IndexEntry {
        let id: String
        let threadName: String
        let updatedAt: Date?
    }

    /// Incremental parsing state per session
    private struct IncrementalState {
        var lastFileOffset: UInt64 = 0
        var messages: [ChatMessage] = []
        var seenCallIds: Set<String> = []
        var callIdToName: [String: String] = [:]
        var completedToolIds: Set<String> = []
        var toolResults: [String: ConversationParser.ToolResult] = [:]
        var syntheticMessageIndex: Int = 0
    }

    private init() {}

    // MARK: - Path Resolution

    /// Find the JSONL file for a Codex session by searching ~/.codex/sessions/
    private func sessionFilePath(sessionId: String) -> String? {
        let home = NSHomeDirectory()
        let sessionsRoot = home + "/.codex/sessions"
        let fm = FileManager.default

        // sessionId from Codex hooks is the session_id field (UUID format)
        // JSONL filenames are: rollout-YYYY-MM-DDTHH-MM-SS-{sessionId}.jsonl
        // Search recent date directories first
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let today = dateFormatter.string(from: Date())

        // Search today and recent days
        var dirsToSearch: [String] = []
        for i in 0..<7 {
            let date = Date().addingTimeInterval(-Double(i) * 86400)
            let dir = sessionsRoot + "/" + dateFormatter.string(from: date)
            if fm.fileExists(atPath: dir) {
                dirsToSearch.append(dir)
            }
        }

        // Also search any directory that exists
        if let yearDirs = try? fm.contentsOfDirectory(atPath: sessionsRoot) {
            for year in yearDirs {
                let yearPath = sessionsRoot + "/" + year
                if let monthDirs = try? fm.contentsOfDirectory(atPath: yearPath) {
                    for month in monthDirs {
                        let monthPath = yearPath + "/" + month
                        if let dayDirs = try? fm.contentsOfDirectory(atPath: monthPath) {
                            for day in dayDirs {
                                let dayPath = monthPath + "/" + day
                                if !dirsToSearch.contains(dayPath) {
                                    dirsToSearch.append(dayPath)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Search each directory for files matching the session ID
        for dir in dirsToSearch {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".jsonl") && file.contains(sessionId) {
                return dir + "/" + file
            }
        }

        return nil
    }

    // MARK: - ConversationInfo

    /// Parse conversation metadata from session index and JSONL
    func parse(sessionId: String, cwd: String) -> ConversationInfo {
        let indexPath = NSHomeDirectory() + "/.codex/session_index.jsonl"

        // Load index if not cached (or stale)
        if indexPathCache == nil || Date().timeIntervalSince(indexPathCache!.loadedAt) > 30 {
            indexPathCache = loadIndex(path: indexPath)
        }

        // Find the freshest thread title from the session index.
        let entry = indexPathCache?.entries
            .filter { $0.id == sessionId }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .first
        let threadName = entry?.threadName

        var lastMessage: String?
        var lastMessageRole: String?
        var firstUserMessage: String?
        var latestUserMessage: String?

        let messages = parseFullConversation(sessionId: sessionId, cwd: cwd)
        for message in messages {
            let text = message.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if message.role == .user {
                if firstUserMessage == nil {
                    firstUserMessage = ConversationParser.truncateMessageStatic(text, maxLength: 50)
                }
                latestUserMessage = ConversationParser.truncateMessageStatic(text, maxLength: 80)
            }

            lastMessage = text
            lastMessageRole = message.role == .user ? "user" : "assistant"
        }

        let title = threadName ?? latestUserMessage ?? firstUserMessage

        return ConversationInfo(
            summary: title,
            lastMessage: ConversationParser.truncateMessageStatic(lastMessage, maxLength: 80),
            lastMessageRole: lastMessageRole,
            lastToolName: nil,
            firstUserMessage: firstUserMessage,
            latestUserMessage: latestUserMessage,
            lastUserMessageDate: entry?.updatedAt
        )
    }

    // MARK: - Full Conversation

    func parseFullConversation(sessionId: String, cwd: String) -> [ChatMessage] {
        guard let filePath = sessionFilePath(sessionId: sessionId) else {
            return []
        }

        var state = incrementalState[sessionId] ?? IncrementalState()
        _ = parseNewLines(filePath: filePath, state: &state)
        incrementalState[sessionId] = state

        return state.messages
    }

    // MARK: - Incremental Parsing

    struct IncrementalParseResult {
        let newMessages: [ChatMessage]
        let allMessages: [ChatMessage]
        let newCompletedToolIds: Set<String>
        let completedToolIds: Set<String>
        let newToolResults: [String: ConversationParser.ToolResult]
        let toolResults: [String: ConversationParser.ToolResult]
    }

    func parseIncremental(sessionId: String, cwd: String) -> IncrementalParseResult {
        guard let filePath = sessionFilePath(sessionId: sessionId) else {
            return IncrementalParseResult(
                newMessages: [], allMessages: [],
                newCompletedToolIds: [],
                completedToolIds: [],
                newToolResults: [:],
                toolResults: [:]
            )
        }

        var state = incrementalState[sessionId] ?? IncrementalState()
        let delta = parseNewLines(filePath: filePath, state: &state)
        incrementalState[sessionId] = state

        return IncrementalParseResult(
            newMessages: delta.messages,
            allMessages: state.messages,
            newCompletedToolIds: delta.completedToolIds,
            completedToolIds: state.completedToolIds,
            newToolResults: delta.toolResults,
            toolResults: state.toolResults
        )
    }

    // MARK: - Queries

    func completedToolIds(for sessionId: String) -> Set<String> {
        incrementalState[sessionId]?.completedToolIds ?? []
    }

    func toolResults(for sessionId: String) -> [String: ConversationParser.ToolResult] {
        incrementalState[sessionId]?.toolResults ?? [:]
    }

    func resetState(for sessionId: String) {
        incrementalState.removeValue(forKey: sessionId)
    }

    // MARK: - Internal Parsing

    private struct IncrementalDelta {
        var messages: [ChatMessage] = []
        var completedToolIds: Set<String> = []
        var toolResults: [String: ConversationParser.ToolResult] = [:]
    }

    private func parseNewLines(filePath: String, state: inout IncrementalState) -> IncrementalDelta {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return IncrementalDelta()
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return IncrementalDelta()
        }

        // File was truncated (unlikely for Codex but handle gracefully)
        if fileSize < state.lastFileOffset {
            state = IncrementalState()
        }

        if fileSize == state.lastFileOffset {
            return IncrementalDelta()
        }

        do {
            try fileHandle.seek(toOffset: state.lastFileOffset)
        } catch {
            return IncrementalDelta()
        }

        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return IncrementalDelta()
        }

        // Handle incomplete last line
        let endsWithNewline = newContent.hasSuffix("\n")
        let adjustedContent: String
        if endsWithNewline {
            adjustedContent = newContent
        } else {
            if let lastNewline = newContent.lastIndex(of: "\n") {
                adjustedContent = String(newContent[...lastNewline])
                let incompletePart = newContent[newContent.index(after: lastNewline)...]
                let incompleteBytes = UInt64(incompletePart.utf8.count)
                state.lastFileOffset = fileSize - incompleteBytes
            } else {
                return IncrementalDelta()
            }
        }

        let lines = adjustedContent.components(separatedBy: "\n")
        var delta = IncrementalDelta()

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String

            if eventType == "event_msg" {
                guard let payload = json["payload"] as? [String: Any],
                      let msg = parseEventMessage(payload, state: &state) else { continue }
                appendMessage(msg, to: &delta.messages, state: &state)
            } else if eventType == "response_item" {
                guard let payload = json["payload"] as? [String: Any] else { continue }
                let itemType = payload["type"] as? String

                switch itemType {
                case "message":
                    if let msg = parseMessage(payload, state: &state) {
                        appendMessage(msg, to: &delta.messages, state: &state)
                    }

                case "function_call":
                    if let msg = parseFunctionCall(payload, state: &state) {
                        appendMessage(msg, to: &delta.messages, state: &state)
                    }

                case "function_call_output":
                    parseFunctionCallOutput(payload, state: &state, delta: &delta)

                default:
                    break
                }
            }
        }

        if endsWithNewline {
            state.lastFileOffset = fileSize
        }

        return delta
    }

    // MARK: - Message Parsing

    private func parseMessage(_ payload: [String: Any], state: inout IncrementalState) -> ChatMessage? {
        let role = payload["role"] as? String
        guard role == "user" || role == "assistant" else { return nil }

        let itemId = (payload["id"] as? String) ?? nextSyntheticMessageId(prefix: "response", state: &state)
        let timestamp = parseTimestamp(payload["created_at"]) ?? Date()

        var blocks: [MessageBlock] = []

        if let contentArray = payload["content"] as? [[String: Any]] {
            for block in contentArray {
                let expectedType = role == "user" ? "input_text" : "output_text"
                if block["type"] as? String == expectedType,
                   let text = block["text"] as? String {
                    blocks.append(.text(text))
                }
            }
        }

        guard !blocks.isEmpty else { return nil }

        let chatRole: ChatRole = role == "user" ? .user : .assistant

        return ChatMessage(
            id: itemId,
            role: chatRole,
            timestamp: timestamp,
            content: blocks
        )
    }

    private func parseEventMessage(_ payload: [String: Any], state: inout IncrementalState) -> ChatMessage? {
        guard let payloadType = payload["type"] as? String else { return nil }

        let role: ChatRole
        switch payloadType {
        case "user_message":
            role = .user
        case "agent_message":
            role = .assistant
        default:
            return nil
        }

        guard let text = payload["message"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let itemId = (payload["id"] as? String) ?? nextSyntheticMessageId(prefix: "event", state: &state)
        let timestamp = parseTimestamp(payload["created_at"]) ?? Date()

        return ChatMessage(
            id: itemId,
            role: role,
            timestamp: timestamp,
            content: [.text(text)]
        )
    }

    private func parseFunctionCall(_ payload: [String: Any], state: inout IncrementalState) -> ChatMessage? {
        guard let callId = payload["call_id"] as? String,
              let name = payload["name"] as? String else { return nil }

        state.callIdToName[callId] = name

        // Parse arguments as input
        var input: [String: String] = [:]
        if let argsStr = payload["arguments"] as? String,
           let argsData = argsStr.data(using: .utf8),
           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
            for (key, value) in argsDict {
                if let str = value as? String {
                    input[key] = str
                } else if let num = value as? Int {
                    input[key] = String(num)
                } else if let bool = value as? Bool {
                    input[key] = bool ? "true" : "false"
                }
            }
        }

        // Create a ChatMessage for the tool call
        let timestamp = parseTimestamp(payload["created_at"]) ?? Date()

        if !state.seenCallIds.contains(callId) {
            state.seenCallIds.insert(callId)

            let toolBlock = ToolUseBlock(id: callId, name: name, input: input)
            return ChatMessage(
                id: "tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(toolBlock)]
            )
        }
        return nil
    }

    private func parseFunctionCallOutput(
        _ payload: [String: Any],
        state: inout IncrementalState,
        delta: inout IncrementalDelta
    ) {
        guard let callId = payload["call_id"] as? String else { return }

        state.completedToolIds.insert(callId)
        delta.completedToolIds.insert(callId)

        let output = payload["output"] as? String
        let result = ConversationParser.ToolResult(
            content: output,
            stdout: nil,
            stderr: nil,
            isError: false
        )
        state.toolResults[callId] = result
        delta.toolResults[callId] = result
    }

    private func appendMessage(_ message: ChatMessage, to newMessages: inout [ChatMessage], state: inout IncrementalState) {
        if let last = state.messages.last,
           last.role == message.role,
           last.textContent == message.textContent,
           !last.textContent.isEmpty {
            return
        }

        state.messages.append(message)
        newMessages.append(message)
    }

    private func nextSyntheticMessageId(prefix: String, state: inout IncrementalState) -> String {
        defer { state.syntheticMessageIndex += 1 }
        return "\(prefix)-msg-\(state.syntheticMessageIndex)"
    }

    // MARK: - Helpers

    private func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }

    private func loadIndex(path: String) -> IndexCache? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var entries: [IndexEntry] = []
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = json["id"] as? String,
                  let threadName = json["thread_name"] as? String else { continue }

            let updatedAt = (json["updated_at"] as? String).flatMap { formatter.date(from: $0) }
            entries.append(IndexEntry(id: id, threadName: threadName, updatedAt: updatedAt))
        }

        return IndexCache(entries: entries, loadedAt: Date())
    }
}

// MARK: - Static helper for truncation (shared with ConversationParser)

private extension ConversationParser {
    static func truncateMessageStatic(_ message: String?, maxLength: Int = 80) -> String? {
        guard let msg = message else { return nil }
        let cleaned = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength - 3)) + "..."
        }
        return cleaned
    }
}
