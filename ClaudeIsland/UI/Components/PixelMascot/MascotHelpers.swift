//
//  MascotHelpers.swift
//  ClaudeIsland
//
//  Shared helpers for pixel mascot views — coordinate mapping,
//  keyframe interpolation, and floating-Z sleep animation.
//  Adapted from CodeIsland2's MascotView pattern.
//

import SwiftUI

// MARK: - Coordinate Helper

/// Maps SVG-unit coordinates to view points with configurable viewport.
struct MascotV {
    let ox: CGFloat, oy: CGFloat, s: CGFloat
    let y0: CGFloat

    init(_ sz: CGSize, svgW: CGFloat = 15, svgH: CGFloat = 10, svgY0: CGFloat = 6) {
        s = min(sz.width / svgW, sz.height / svgH)
        ox = (sz.width - svgW * s) / 2
        oy = (sz.height - svgH * s) / 2
        y0 = svgY0
    }

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
        CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
    }

    func pt(_ x: CGFloat, _ y: CGFloat, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: ox + x * s, y: oy + (y - y0 + dy) * s)
    }
}

// MARK: - Keyframe Interpolation

/// Linearly interpolate between keyframe pairs [(percentage, value)].
func mascotLerp(_ keyframes: [(CGFloat, CGFloat)], at pct: CGFloat) -> CGFloat {
    guard let first = keyframes.first else { return 0 }
    if pct <= first.0 { return first.1 }
    for i in 1..<keyframes.count {
        if pct <= keyframes[i].0 {
            let t = (pct - keyframes[i - 1].0) / (keyframes[i].0 - keyframes[i - 1].0)
            return keyframes[i - 1].1 + (keyframes[i].1 - keyframes[i - 1].1) * t
        }
    }
    return keyframes.last?.1 ?? 0
}

// MARK: - Floating Z's Animation

/// Renders 3 floating "z" characters that loop upward — used for sleep scenes.
struct FloatingZsView: View {
    let t: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let ci = Double(i)
                let cycle = 2.8 + ci * 0.3
                let delay = ci * 0.9
                let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle)
                let fontSize = max(6, size * CGFloat(0.18 + phase * 0.10))
                let baseOp = 0.7 - ci * 0.1
                let opacity = phase < 0.8 ? baseOp : (1.0 - phase) * 3.5 * baseOp
                Text("z")
                    .font(.system(size: fontSize, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .offset(
                        x: size * CGFloat(0.08 + ci * 0.06 + sin(phase * .pi * 2) * 0.03),
                        y: -size * CGFloat(0.15 + phase * 0.38)
                    )
            }
        }
    }
}

// MARK: - AnimationState → Scene Mapping

/// Groups AnimationState into 3 scene types used by pixel mascots.
enum MascotScene {
    case sleep
    case work
    case alert
}

extension AnimationState {
    var mascotScene: MascotScene {
        switch self {
        case .idle, .done:
            return .sleep
        case .working, .thinking:
            return .work
        case .needsYou, .error:
            return .alert
        }
    }
}
