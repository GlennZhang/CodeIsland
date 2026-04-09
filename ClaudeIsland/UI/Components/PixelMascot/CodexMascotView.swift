//
//  CodexMascotView.swift
//  ClaudeIsland
//
//  Dex — Codex mascot, pixel-art cloud with terminal prompt face.
//  Inspired by Codex's cloud icon with `>_` symbol. OpenAI black & white style.
//  Adapted from CodeIsland2's DexView.
//

import SwiftUI

struct CodexMascotView: View {
    let state: AnimationState
    var size: CGFloat = 27
    @State private var alive = false

    private static let cloudC = Color(red: 0.92, green: 0.92, blue: 0.93)
    private static let cloudDark = Color(red: 0.70, green: 0.70, blue: 0.72)
    private static let promptC = Color.black
    private static let alertC = Color(red: 1.0, green: 0.55, blue: 0.0)
    private static let kbBase = Color(red: 0.18, green: 0.18, blue: 0.20)
    private static let kbKey = Color(red: 0.40, green: 0.40, blue: 0.42)
    private static let kbHi = Color.white

    var body: some View {
        ZStack {
            switch state.mascotScene {
            case .sleep: sleepScene
            case .work: workScene
            case .alert: alertScene
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: state) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.05) { alive = true }
        }
    }

    // MARK: - Cloud Body

    private func drawCloud(_ c: GraphicsContext, v: MascotV, dy: CGFloat,
                           squashX: CGFloat = 1, squashY: CGFloat = 1)
    {
        let cc = Self.cloudC
        let cx: CGFloat = 7.5

        func sx(_ x: CGFloat, w: CGFloat) -> (CGFloat, CGFloat) {
            let nx = cx + (x - cx) * squashX
            return (nx, w * squashX)
        }

        let rows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (14, 4, 7), (13, 3, 9), (12, 2, 11), (11, 1, 13), (10, 1, 13),
            (9, 1, 13), (8, 2, 11), (7, 2, 11),
            (6, 3, 3), (6, 6, 3), (6, 9, 3),
            (5, 4, 2), (5, 6.5, 2), (5, 9, 2),
        ]

        for row in rows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            let adjH: CGFloat = 1 * squashY
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 10, adjW, adjH, dy: dy)),
                   with: .color(cc))
        }
    }

    private func drawPrompt(_ c: GraphicsContext, v: MascotV, dy: CGFloat,
                            color: Color = Self.promptC, cursorOn: Bool = true)
    {
        c.fill(Path(v.r(3, 10, 1, 1, dy: dy)), with: .color(color))
        c.fill(Path(v.r(4, 11, 1, 1, dy: dy)), with: .color(color))
        c.fill(Path(v.r(3, 12, 1, 1, dy: dy)), with: .color(color))
        if cursorOn {
            c.fill(Path(v.r(6, 12, 3, 1, dy: dy)), with: .color(color))
        }
    }

    private func drawShadow(_ c: GraphicsContext, v: MascotV, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: MascotV) {
        c.fill(Path(v.r(5, 14.5, 1, 1.5)), with: .color(Self.cloudDark))
        c.fill(Path(v.r(9, 14.5, 1, 1.5)), with: .color(Self.cloudDark))
    }

    // MARK: - Sleep

    private var sleepScene: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                sleepCanvas(t: t)
            }
            TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                FloatingZsView(t: ctx.date.timeIntervalSinceReferenceDate, size: size)
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        let phase = t.truncatingRemainder(dividingBy: 4.0) / 4.0
        let float = sin(phase * .pi * 2) * 0.8
        let cursorPhase = t.truncatingRemainder(dividingBy: 1.2)
        let cursorOn = cursorPhase < 0.6

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 7 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v)
            drawCloud(c, v: v, dy: float)
            if cursorOn {
                c.fill(Path(v.r(6, 12, 3, 1, dy: float)),
                       with: .color(Self.promptC.opacity(0.3)))
            }
        }
    }

    // MARK: - Work

    private var workScene: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0
        let cursorPhase = t.truncatingRemainder(dividingBy: 0.3)
        let cursorOn = cursorPhase < 0.15
        let keyPhase = Int(t / 0.1) % 6

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 14, svgY0: 3)
            let dy = bounce

            let shadowW: CGFloat = 8 - abs(dy) * 0.3
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(dy) * 0.03))))

            drawLegs(c, v: v)

            c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
            for row in 0..<2 {
                let ky = 13.5 + CGFloat(row) * 1.2
                for col in 0..<6 {
                    let kx = 0.5 + CGFloat(col) * 2.4
                    c.fill(Path(v.r(kx, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                }
            }
            let flashRow = keyPhase / 3
            let flashCol = keyPhase % 6
            c.fill(Path(v.r(0.5 + CGFloat(flashCol) * 2.4, 13.5 + CGFloat(flashRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawCloud(c, v: v, dy: dy)
            drawPrompt(c, v: v, dy: dy, cursorOn: cursorOn)
        }
    }

    // MARK: - Alert

    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)

            TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                alertCanvas(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func alertCanvas(t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        let pct = cycle / 3.5

        let jumpY = mascotLerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -8), (0.20, -8), (0.25, 1.5),
            (0.275, -6), (0.30, -6), (0.35, 1.0),
            (0.375, -4), (0.40, -4), (0.45, 0.8),
            (0.475, -2), (0.50, -2), (0.55, 0.3),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        let squashX: CGFloat = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
        let squashY: CGFloat = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0
        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0

        let flash = (pct > 0.03 && pct < 0.55) ? sin(pct * 25) * 0.5 + 0.5 : 0.0
        let promptColor = flash > 0.5 ? Self.alertC : Self.promptC

        let bangOp = mascotLerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = mascotLerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawCloud(c, v: v, dy: jumpY, squashX: squashX, squashY: squashY)
            drawPrompt(c, v: v, dy: jumpY, color: promptColor, cursorOn: true)
            c.translateBy(x: -shakeX * v.s, y: 0)

            if bangOp > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 13
                let by: CGFloat = 4 + jumpY * 0.15
                c.fill(Path(v.r(bx, by, bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale, bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
            }
        }
    }
}
