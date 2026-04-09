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

        // Find thread name from index
        let entry = indexPathCache?.entries.first { $0.id == sessionId }
        let threadName = entry?.threadName

        // Parse last message from JSONL
        var lastMessage: String?
        var lastMessageRole: String?
        var firstUserMessage: String?

        if let filePath = sessionFilePath(sessionId: sessionId),
           let content = FileManager.default.contents(atPath: filePath),
           let text = String(data: content, encoding: .utf8) {
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "response_item",
                      let payload = json["payload"] as? [String: Any],
                      payload["type"] as? String == "message" else { continue }

                let role = payload["role"] as? String
                if role == "user" {
                    if let contentArray = payload["content"] as? [[String: Any]] {
                        for block in contentArray {
                            if block["type"] as? String == "output_text",
                               let text = block["text"] as? String {
                                if firstUserMessage == nil {
                                    firstUserMessage = String(text.prefix(50))
                                }
                                lastMessage = text
                                lastMessageRole = "user"
                            }
                        }
                    }
                } else if role == "assistant" {
                    if let contentArray = payload["content"] as? [[String: Any]] {
                        for block in contentArray {
                            if block["type"] as? String == "output_text",
                               let text = block["text"] as? String {
                                lastMessage = text
                                lastMessageRole = "assistant"
                            }
                        }
                    }
                }
            }
        }

        let title = threadName ?? firstUserMessage

        return ConversationInfo(
            summary: title,
            lastMessage: ConversationParser.truncateMessageStatic(lastMessage, maxLength: 80),
            lastMessageRole: lastMessageRole,
            lastToolName: nil,
            firstUserMessage: firstUserMessage,
            latestUserMessage: firstUserMessage,
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
        let completedToolIds: Set<String>
        let toolResults: [String: ConversationParser.ToolResult]
    }

    func parseIncremental(sessionId: String, cwd: String) -> IncrementalParseResult {
        guard let filePath = sessionFilePath(sessionId: sessionId) else {
            return IncrementalParseResult(
                newMessages: [], allMessages: [],
                completedToolIds: [], toolResults: [:]
            )
        }

        var state = incrementalState[sessionId] ?? IncrementalState()
        let newMessages = parseNewLines(filePath: filePath, state: &state)
        incrementalState[sessionId] = state

        return IncrementalParseResult(
            newMessages: newMessages,
            allMessages: state.messages,
            completedToolIds: state.completedToolIds,
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

    private func parseNewLines(filePath: String, state: inout IncrementalState) -> [ChatMessage] {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return []
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return []
        }

        // File was truncated (unlikely for Codex but handle gracefully)
        if fileSize < state.lastFileOffset {
            state = IncrementalState()
        }

        if fileSize == state.lastFileOffset {
            return []
        }

        do {
            try fileHandle.seek(toOffset: state.lastFileOffset)
        } catch {
            return state.messages
        }

        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return state.messages
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
                return []
            }
        }

        let lines = adjustedContent.components(separatedBy: "\n")
        var newMessages: [ChatMessage] = []

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String

            if eventType == "response_item" {
                guard let payload = json["payload"] as? [String: Any] else { continue }
                let itemType = payload["type"] as? String

                switch itemType {
                case "message":
                    if let msg = parseMessage(payload) {
                        newMessages.append(msg)
                        state.messages.append(msg)
                    }

                case "function_call":
                    parseFunctionCall(payload, state: &state)

                case "function_call_output":
                    parseFunctionCallOutput(payload, state: &state)

                default:
                    break
                }
            }
        }

        if endsWithNewline {
            state.lastFileOffset = fileSize
        }

        return newMessages
    }

    // MARK: - Message Parsing

    private func parseMessage(_ payload: [String: Any]) -> ChatMessage? {
        let role = payload["role"] as? String
        guard let itemId = payload["id"] as? String else { return nil }

        // Only parse user and assistant messages
        guard role == "user" || role == "assistant" else { return nil }

        let timestamp = parseTimestamp(payload["created_at"]) ?? Date()

        var blocks: [MessageBlock] = []

        if let contentArray = payload["content"] as? [[String: Any]] {
            for block in contentArray {
                if block["type"] as? String == "output_text",
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

    private func parseFunctionCall(_ payload: [String: Any], state: inout IncrementalState) {
        guard let callId = payload["call_id"] as? String,
              let name = payload["name"] as? String else { return }

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
            let message = ChatMessage(
                id: "tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(toolBlock)]
            )
            state.messages.append(message)
        }
    }

    private func parseFunctionCallOutput(_ payload: [String: Any], state: inout IncrementalState) {
        guard let callId = payload["call_id"] as? String else { return }

        state.completedToolIds.insert(callId)

        let output = payload["output"] as? String
        state.toolResults[callId] = ConversationParser.ToolResult(
            content: output,
            stdout: nil,
            stderr: nil,
            isError: false
        )
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
