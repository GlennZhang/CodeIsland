//
//  ConnectionStatus.swift
//  ClaudeIsland
//
//  Distinguishes how a session became visible from its runtime phase.
//

enum ConnectionStatus: String, Codable, Sendable, Equatable {
    case discovered
    case connected

    var isDiscovered: Bool { self == .discovered }
}
