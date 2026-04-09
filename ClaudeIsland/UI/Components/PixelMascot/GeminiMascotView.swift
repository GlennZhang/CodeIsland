//
//  GeminiMascotView.swift
//  ClaudeIsland
//
//  Gemini — Google Gemini CLI mascot, four-pointed sparkle star.
//  Blue→Purple→Rose gradient (#4796E4 → #847ACE → #C3677F).
//  Adapted from CodeIsland2's GeminiView.
//

import SwiftUI

struct GeminiMascotView: View {
    let state: AnimationState
    var size: CGFloat = 27
    @State private var alive = false

    private static let blueC = Color(red: 0.278, green: 0.588, blue: 0.894)
    private static let purpC = Color(red: 0.518, green: 0.478, blue: 0.808)
    private static let roseC = Color(red: 0.765, green: 0.404, blue: 0.498)
    private static let faceC = Color.white
    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase = Color(red: 0.22, green: 0.25, blue: 0.38)
    private static let kbKey = Color(red: 0.40, green: 0.44, blue: 0.58)
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

    // MARK: - Star Body

    private func drawStar(_ c: GraphicsContext, v: MascotV, dy: CGFloat,
                          scale: CGFloat = 1.0, rotate: CGFloat = 0)
    {
        let cx: CGFloat = 7.5, cy: CGFloat = 10.0
        let outerR: CGFloat = 4.5 * scale
        let innerR: CGFloat = 1.8 * scale
        let rot = rotate * .pi / 180

        var path = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2 + rot
            let r = i % 2 == 0 ? outerR : innerR
            let px = cx + cos(angle) * r
            let py = cy + sin(angle) * r
            let pt = CGPoint(x: v.ox + px * v.s, y: v.oy + (py - v.y0 + dy) * v.s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()

        let topPt = CGPoint(x: v.ox + (cx - outerR) * v.s, y: v.oy + (cy - outerR - v.y0 + dy) * v.s)
        let botPt = CGPoint(x: v.ox + (cx + outerR) * v.s, y: v.oy + (cy + outerR - v.y0 + dy) * v.s)
        c.fill(path, with: .linearGradient(
            Gradient(colors: [Self.blueC, Self.purpC, Self.roseC]),
            startPoint: topPt, endPoint: botPt))
    }

    private func drawFace(_ c: GraphicsContext, v: MascotV, dy: CGFloat,
                          eyeScale: CGFloat = 1.0, blinkPhase: CGFloat = 1.0)
    {
        let eyeH: CGFloat = 1.5 * eyeScale * blinkPhase
        let eyeY: CGFloat = 9.5 + (1.5 - eyeH) / 2
        c.fill(Path(v.r(5.5, eyeY, 1.2, max(0.3, eyeH), dy: dy)), with: .color(Self.faceC))
        c.fill(Path(v.r(8.3, eyeY, 1.2, max(0.3, eyeH), dy: dy)), with: .color(Self.faceC))
    }

    private func drawShadow(_ c: GraphicsContext, v: MascotV, width: CGFloat = 7, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: MascotV, dy: CGFloat = 0) {
        let legDy = dy * 0.3
        c.fill(Path(v.r(5.5, 14, 1, 2, dy: legDy)), with: .color(Self.purpC.opacity(0.7)))
        c.fill(Path(v.r(8.5, 14, 1, 2, dy: legDy)), with: .color(Self.purpC.opacity(0.7)))
    }

    // MARK: - Sleep

    private var sleepScene: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                sleepCanvas(t: ctx.date.timeIntervalSinceReferenceDate)
            }
            TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                FloatingZsView(t: ctx.date.timeIntervalSinceReferenceDate, size: size)
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        let phase = t.truncatingRemainder(dividingBy: 4.0) / 4.0
        let float = sin(phase * .pi * 2) * 0.8
        let slowSpin = sin(phase * .pi * 2) * 5
        let blinkCycle = t.truncatingRemainder(dividingBy: 4.0)
        let blink: CGFloat = (blinkCycle > 3.5 && blinkCycle < 3.7) ? 0.15 : 0.5

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 6 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v, dy: float)
            drawStar(c, v: v, dy: float, scale: 0.9, rotate: slowSpin)
            drawFace(c, v: v, dy: float, blinkPhase: blink)
        }
    }

    // MARK: - Work

    private var workScene: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
            workCanvas(t: ctx.date.timeIntervalSinceReferenceDate)
        }
    }

    private func workCanvas(t: Double) -> some View {
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0
        let spin = sin(t * 2 * .pi / 1.2) * 15
        let blinkCycle = t.truncatingRemainder(dividingBy: 2.5)
        let blink: CGFloat = (blinkCycle > 2.2 && blinkCycle < 2.35) ? 0.1 : 1.0
        let keyPhase = Int(t / 0.1) % 6

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 14, svgY0: 3)
            let dy = bounce

            let shadowW: CGFloat = 7 - abs(dy) * 0.3
            c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(dy) * 0.03))))

            drawLegs(c, v: v, dy: dy)

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

            drawStar(c, v: v, dy: dy, scale: 1.0, rotate: spin)
            drawFace(c, v: v, dy: dy, blinkPhase: blink)
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

        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0
        let pulseScale: CGFloat = (pct > 0.03 && pct < 0.55)
            ? 1.0 + sin(pct * 20) * 0.15 : 1.0

        let bangOp = mascotLerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = mascotLerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 7 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v, dy: jumpY)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawStar(c, v: v, dy: jumpY, scale: pulseScale, rotate: 0)
            drawFace(c, v: v, dy: jumpY, eyeScale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0)
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
