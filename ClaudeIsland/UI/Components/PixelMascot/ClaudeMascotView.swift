//
//  ClaudeMascotView.swift
//  ClaudeIsland
//
//  Clawd — Claude mascot, a small desk-worker character adapted from
//  CodeIsland2's ClawdView. Used by MascotRouterView in multi-mascot mode.
//

import SwiftUI

struct ClaudeMascotView: View {
    let state: AnimationState
    var size: CGFloat = 27
    @State private var alive = false

    private static let bodyC = Color(red: 0.871, green: 0.533, blue: 0.427)
    private static let eyeC = Color.black
    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase = Color(red: 0.38, green: 0.44, blue: 0.50)
    private static let kbKey = Color(red: 0.60, green: 0.66, blue: 0.72)
    private static let kbHi = Color.white

    var body: some View {
        ZStack {
            switch state.mascotScene {
            case .sleep:
                sleepScene
            case .work:
                workScene
            case .alert:
                alertScene
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: state) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                alive = true
            }
        }
    }

    private func armPath(
        _ v: MascotV,
        x: CGFloat,
        y: CGFloat,
        w: CGFloat,
        h: CGFloat,
        pivotX: CGFloat,
        pivotY: CGFloat,
        angle: CGFloat,
        dy: CGFloat
    ) -> Path {
        let radians = angle * .pi / 180
        let ca = cos(radians)
        let sa = sin(radians)
        let corners: [(CGFloat, CGFloat)] = [
            (x - pivotX, y - pivotY),
            (x + w - pivotX, y - pivotY),
            (x + w - pivotX, y + h - pivotY),
            (x - pivotX, y + h - pivotY)
        ]

        var path = Path()
        for (index, corner) in corners.enumerated() {
            let rx = corner.0 * ca - corner.1 * sa + pivotX
            let ry = corner.0 * sa + corner.1 * ca + pivotY
            let point = v.pt(rx, ry, dy: dy)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
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
        let phase = t.truncatingRemainder(dividingBy: 4.5) / 4.5
        let breathe: CGFloat = phase < 0.4 ? CGFloat(sin(phase / 0.4 * .pi)) : 0

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 17, svgH: 7, svgY0: 9)
            let puff = max(0, breathe) * 0.25
            let torsoH: CGFloat = 5 * (1.0 + puff)
            let torsoW: CGFloat = 13 * (1.0 + breathe * 0.015)

            c.fill(Path(v.r(-1, 15, 17 * (1 + breathe * 0.03), 1)),
                   with: .color(.black.opacity(0.35 + breathe * 0.08)))

            for x: CGFloat in [3, 5, 9, 11] {
                c.fill(Path(v.r(x, 8.5, 1, 1.5)), with: .color(Self.bodyC))
            }

            c.fill(Path(v.r(1 - (torsoW - 13) / 2, 15 - torsoH, torsoW, torsoH)),
                   with: .color(Self.bodyC))
            c.fill(Path(v.r(-1, 13, 2, 2)), with: .color(Self.bodyC))
            c.fill(Path(v.r(14, 13, 2, 2)), with: .color(Self.bodyC))

            let eyeY: CGFloat = 12.2 - puff * 2.5
            c.fill(Path(v.r(3, eyeY, 2.5, 1)), with: .color(Self.eyeC))
            c.fill(Path(v.r(9.5, eyeY, 2.5, 1)), with: .color(Self.eyeC))
        }
    }

    // MARK: - Work

    private var workScene: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
            workCanvas(t: ctx.date.timeIntervalSinceReferenceDate)
        }
    }

    private func workCanvas(t: Double) -> some View {
        let bounce = CGFloat(sin(t * 2 * .pi / 0.35)) * 1.2
        let breathe = CGFloat(sin(t * 2 * .pi / 3.2))
        let armLRaw = CGFloat(sin(t * 2 * .pi / 0.15))
        let armRRaw = CGFloat(sin(t * 2 * .pi / 0.12))
        let armL = armLRaw * 22.5 - 32.5
        let armR = armRRaw * 22.5 + 32.5
        let blinkPhase = t.truncatingRemainder(dividingBy: 3.5)
        let eyeH: CGFloat = (blinkPhase > 1.4 && blinkPhase < 1.55) ? 0.2 : 1.0

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 11, svgY0: 5.5)
            let dy = bounce
            let shadowW = 9 - abs(dy) * 0.3

            c.fill(Path(v.r(3 + (9 - shadowW) / 2, 15, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.4 - abs(dy) * 0.03))))

            for x: CGFloat in [3, 5, 9, 11] {
                c.fill(Path(v.r(x, 13, 1, 2)), with: .color(Self.bodyC))
            }

            let torsoW = 11 * (1.0 + breathe * 0.015)
            c.fill(Path(v.r(2 - (torsoW - 11) / 2, 6, torsoW, 7, dy: dy)),
                   with: .color(Self.bodyC))

            c.fill(Path(v.r(4, 9, 1, eyeH, dy: dy)), with: .color(Self.eyeC))
            c.fill(Path(v.r(10, 9, 1, eyeH, dy: dy)), with: .color(Self.eyeC))

            c.fill(Path(v.r(-0.5, 11.8, 16, 3.5)), with: .color(Self.kbBase))
            for row in 0..<3 {
                for col in 0..<6 {
                    c.fill(Path(v.r(0.3 + CGFloat(col) * 2.5, 12.2 + CGFloat(row), 2.0, 0.7)),
                           with: .color(Self.kbKey))
                }
            }

            if armLRaw > 0.3 {
                let col = Int(t / 0.15) % 3
                c.fill(Path(v.r(0.3 + CGFloat(col) * 2.5, 12.2 + CGFloat(col % 3), 2, 0.7)),
                       with: .color(Self.kbHi.opacity(0.9)))
            }
            if armRRaw > 0.3 {
                let col = 3 + Int(t / 0.12) % 3
                c.fill(Path(v.r(0.3 + CGFloat(col) * 2.5, 12.2 + CGFloat((col - 3) % 3), 2, 0.7)),
                       with: .color(Self.kbHi.opacity(0.9)))
            }

            c.fill(armPath(v, x: 0, y: 9, w: 2, h: 2, pivotX: 2, pivotY: 10, angle: armL, dy: dy),
                   with: .color(Self.bodyC))
            c.fill(armPath(v, x: 13, y: 9, w: 2, h: 2, pivotX: 13, pivotY: 10, angle: armR, dy: dy),
                   with: .color(Self.bodyC))
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
        let pct = CGFloat(t.truncatingRemainder(dividingBy: 3.5) / 3.5)
        let jumpY = mascotLerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -10), (0.20, -10), (0.25, 1.5),
            (0.30, -8), (0.35, 1.2), (0.40, -5),
            (0.50, -3), (0.62, 0), (1.0, 0)
        ], at: pct)
        let arm = mascotLerp([
            (0, 0), (0.10, 25), (0.20, 155), (0.35, 100),
            (0.50, 80), (0.62, 0), (1.0, 0)
        ], at: pct)

        return Canvas { c, sz in
            let v = MascotV(sz, svgW: 16, svgH: 11, svgY0: 5.5)
            c.fill(Path(v.r(3, 15, 9 * max(0.45, 1 - abs(min(0, jumpY)) * 0.04), 1)),
                   with: .color(.black.opacity(0.35)))

            for x: CGFloat in [3, 5, 9, 11] {
                c.fill(Path(v.r(x, 13, 1, 2)), with: .color(Self.bodyC))
            }
            c.fill(Path(v.r(2, 6, 11, 7, dy: jumpY)), with: .color(Self.bodyC))
            c.fill(Path(v.r(4, 8, 1.4, 2.2, dy: jumpY)), with: .color(Self.eyeC))
            c.fill(Path(v.r(9.6, 8, 1.4, 2.2, dy: jumpY)), with: .color(Self.eyeC))

            c.fill(armPath(v, x: 0, y: 9, w: 2, h: 2, pivotX: 2, pivotY: 10, angle: arm, dy: jumpY),
                   with: .color(Self.bodyC))
            c.fill(armPath(v, x: 13, y: 9, w: 2, h: 2, pivotX: 13, pivotY: 10, angle: -arm, dy: jumpY),
                   with: .color(Self.bodyC))

            c.fill(Path(v.r(13, 4 + jumpY * 0.15, 2, 4)), with: .color(Self.alertC))
            c.fill(Path(v.r(13, 9 + jumpY * 0.15, 2, 1.5)), with: .color(Self.alertC))
        }
    }
}
