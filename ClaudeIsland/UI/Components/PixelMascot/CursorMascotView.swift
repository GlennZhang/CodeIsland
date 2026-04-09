//
//  CursorMascotView.swift
//  ClaudeIsland
//
//  CursorBot — Cursor AI mascot, pixel-art hexagonal gem with diagonal highlight.
//  Warm dark #14120B body, light face #EDECEC highlight.
//  Adapted from CodeIsland2's CursorView.
//

import SwiftUI

struct CursorMascotView: View {
    let state: AnimationState
    var size: CGFloat = 27
    @State private var alive = false

    private static let darkC = Color(red: 0.08, green: 0.07, blue: 0.04)
    private static let midC = Color(red: 0.15, green: 0.14, blue: 0.12)
    private static let lightC = Color(red: 0.93, green: 0.93, blue: 0.93)
    private static let edgeC = Color(red: 0.30, green: 0.28, blue: 0.24)
    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase = Color(red: 0.12, green: 0.11, blue: 0.08)
    private static let kbKey = Color(red: 0.30, green: 0.28, blue: 0.22)
    private static let kbHi = Color(red: 0.93, green: 0.93, blue: 0.93)

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

    // MARK: - Gem Body

    private func drawGem(_ c: GraphicsContext, v: MascotV, dy: CGFloat, shimmer: CGFloat = 0) {
        let cx: CGFloat = 7.5, cy: CGFloat = 10.0
        let rx: CGFloat = 5.0, ry: CGFloat = 4.5

        let top = v.pt(cx, cy - ry, dy: dy)
        let topR = v.pt(cx + rx, cy - ry * 0.45, dy: dy)
        let botR = v.pt(cx + rx, cy + ry * 0.45, dy: dy)
        let bot = v.pt(cx, cy + ry, dy: dy)
        let botL = v.pt(cx - rx, cy + ry * 0.45, dy: dy)
        let topL = v.pt(cx - rx, cy - ry * 0.45, dy: dy)
        let center = v.pt(cx, cy, dy: dy)

        var leftTop = Path()
        leftTop.move(to: topL); leftTop.addLine(to: top)
        leftTop.addLine(to: center); leftTop.addLine(to: botL); leftTop.closeSubpath()
        c.fill(leftTop, with: .color(Self.darkC))

        var rightFacet = Path()
        rightFacet.move(to: top); rightFacet.addLine(to: topR)
        rightFacet.addLine(to: botR); rightFacet.addLine(to: center); rightFacet.closeSubpath()
        c.fill(rightFacet, with: .color(Self.midC))

        var bottomFacet = Path()
        bottomFacet.move(to: botL); bottomFacet.addLine(to: center)
        bottomFacet.addLine(to: botR); bottomFacet.addLine(to: bot); bottomFacet.closeSubpath()
        c.fill(bottomFacet, with: .color(Self.edgeC))

        let hlAlpha = 0.7 + shimmer * 0.3
        var highlight = Path()
        highlight.move(to: v.pt(cx + 1, cy - ry + 0.5, dy: dy))
        highlight.addLine(to: v.pt(cx + rx - 0.5, cy - ry * 0.45 + 0.3, dy: dy))
        highlight.addLine(to: v.pt(cx + 0.5, cy + 0.5, dy: dy))
        highlight.closeSubpath()
        c.fill(highlight, with: .color(Self.lightC.opacity(hlAlpha)))

        var outline = Path()
        outline.move(to: top); outline.addLine(to: topR)
        outline.addLine(to: botR); outline.addLine(to: bot)
        outline.addLine(to: botL); outline.addLine(to: topL)
        outline.closeSubpath()
        c.stroke(outline, with: .color(Self.lightC.opacity(0.35)), lineWidth: v.s * 0.5)
    }

    private func drawEyes(_ c: GraphicsContext, v: MascotV, dy: CGFloat,
                          scale: CGFloat = 1.0, color: Color = Self.lightC)
    {
        let eyeH: CGFloat = 1.3 * scale
        let eyeY: CGFloat = 9.5 + (1.3 - eyeH) / 2
        c.fill(Path(v.r(4.2, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(color))
        c.fill(Path(v.r(6.8, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(color))
    }

    private func drawShadow(_ c: GraphicsContext, v: MascotV, width: CGFloat = 8, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15.5, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: MascotV) {
        c.fill(Path(v.r(5.5, 14.5, 1, 1.5)), with: .color(Self.edgeC))
        c.fill(Path(v.r(8.5, 14.5, 1, 1.5)), with: .color(Self.edgeC))
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
        let float = sin(phase * .pi * 2) * 0.6

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 7 + abs(float) * 0.2, opacity: 0.2)
            drawLegs(c, v: v)
            drawGem(c, v: v, dy: float)
            drawEyes(c, v: v, dy: float, scale: 0.3, color: Self.lightC.opacity(0.4))
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
        let shimmer = sin(t * 2 * .pi / 1.5) * 0.5 + 0.5
        let blinkCycle = t.truncatingRemainder(dividingBy: 3.0)
        let blink: CGFloat = (blinkCycle > 2.6 && blinkCycle < 2.75) ? 0.1 : 1.0
        let keyPhase = Int(t / 0.1) % 6

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 - abs(bounce) * 0.3
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(bounce) * 0.03))))

            drawLegs(c, v: v)

            c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
            for row in 0..<2 {
                let ky = 13.5 + CGFloat(row) * 1.2
                for col in 0..<6 {
                    let kx = 0.5 + CGFloat(col) * 2.4
                    c.fill(Path(v.r(kx, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                }
            }
            let fCol = keyPhase % 6
            let fRow = keyPhase / 3
            c.fill(Path(v.r(0.5 + CGFloat(fCol) * 2.4, 13.5 + CGFloat(fRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawGem(c, v: v, dy: bounce, shimmer: shimmer)
            drawEyes(c, v: v, dy: bounce, scale: blink)
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
        let shimmer: CGFloat = (pct > 0.03 && pct < 0.55) ? sin(pct * 30) * 0.5 + 0.5 : 0

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
            drawGem(c, v: v, dy: jumpY, shimmer: shimmer)
            let eyeColor: Color = (pct > 0.03 && pct < 0.55 && sin(pct * 25) > 0)
                ? Self.alertC : Self.lightC
            drawEyes(c, v: v, dy: jumpY, scale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0, color: eyeColor)
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
