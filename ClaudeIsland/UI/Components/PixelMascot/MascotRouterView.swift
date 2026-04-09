//
//  MascotRouterView.swift
//  ClaudeIsland
//
//  Routes an AgentType + AnimationState to the correct pixel mascot view.
//  Unknown agents keep the original PixelCharacterView (cat face).
//  Known agents get unique pixel characters adapted from CodeIsland2.
//

import SwiftUI

struct MascotRouterView: View {
    let agentType: AgentType
    let state: AnimationState
    var size: CGFloat = PixelCharacterView.canvasW

    var body: some View {
        switch agentType {
        case .claude:
            ClaudeMascotView(state: state, size: size)
        case .codex:
            CodexMascotView(state: state, size: size)
        case .unknown:
            PixelCharacterView(state: state)
        case .gemini:
            GeminiMascotView(state: state, size: size)
        case .cursor:
            CursorMascotView(state: state, size: size)
        case .opencode:
            OpenCodeMascotView(state: state, size: size)
        }
    }
}
