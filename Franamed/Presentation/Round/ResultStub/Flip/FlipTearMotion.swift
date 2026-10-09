//
//  FlipTearMotion.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 09.10.2026.
//

import CoreGraphics
import QuartzCore
import simd

struct FlipTearMotion {
    private(set) var target = FlipTear.none
    private var state = SIMD3<Float>.zero
    private var tick: TimeInterval?
    private var strain: Float = 0
    private var healStart: SIMD2<Float>?
    private var healElapsed: Double = 0
    private var healGlow: Float = 0
    private var healReach: Float = 0

    private static let tugPeriod: Double = 2.2

    private static let openThreshold: Float = 0.0005

    var isOpen: Bool { state.x > Self.openThreshold }

    var isHealing: Bool {
        target.state == .zero && (isOpen || healGlow > 0)
    }

    var showsMarks: Bool { isOpen || target.scar > 0 }

    var halves: [Float] { isOpen || healGlow > 0 ? [-1, 1] : [0] }

    mutating func setTarget(_ tear: FlipTear) -> Bool {
        guard tear != target else { return false }
        if tear.seed != target.seed { state = .zero }
        target = tear
        return true
    }

    mutating func step(now: TimeInterval) -> Bool {
        let dt = min(now - (tick ?? now), 1.0 / 30.0)
        tick = now
        let goal = target.state
        if goal == .zero, isOpen {
            heal(dt: dt)
        } else {
            healStart = nil
            healElapsed = 0
            let decay: SIMD3<Double> = SIMD3(exp(-dt / 0.07), exp(-dt / 0.12), exp(-dt / 0.16))
            state += (goal - state) * SIMD3<Float>(1 - decay)
        }
        strain += (target.strain - strain) * Float(1 - exp(-dt / 0.3))
        if abs(target.strain - strain) < 0.002 || target.progress >= 1 { strain = target.strain }
        if !isOpen || goal != .zero {
            healGlow *= Float(exp(-dt / 0.35))
            if healGlow < 0.01 { healGlow = 0; healReach = 0 }
        }
        let isShapeSettled = abs(goal - state).max() < 0.0015 && healGlow == 0
        if isShapeSettled { state = goal }
        let isSettled = isShapeSettled && strain == target.strain
        if isSettled { tick = nil }
        return !isSettled || strain > 0
    }

    func uniforms(width: CGFloat, half: Float) -> (line: SIMD4<Float>, shape: SIMD4<Float>,
                                                   state: SIMD4<Float>, heal: SIMD4<Float>) {
        let shape = target.shape(width: width)
        return (shape.line, shape.shape, SIMD4(strainedState, half),
                SIMD4(healGlow, min(healReach, 1), target.scar, 0))
    }

    private mutating func heal(dt: Double) {
        let start = healStart ?? SIMD2(state.x, state.y)
        healStart = start
        healElapsed += dt
        let duration = 0.55 + 0.45 * Double(start.x)
        let t = Float(min(healElapsed / duration, 1))
        let remaining = 1 - t * t * (3 - 2 * t)
        state = SIMD3(start.x * remaining, start.y * remaining.squareRoot(), 0)
        healReach = max(healReach, start.x)
        if isOpen { healGlow = 1 }
    }

    private var strainedState: SIMD3<Float> {
        guard strain > 0 else { return state }
        let now = CACurrentMediaTime()
        let phase = now.truncatingRemainder(dividingBy: Self.tugPeriod)
        let tug = phase < 0.45 ? pow(sin(.pi * phase / 0.45), 2) : 0
        let tremble = 0.06 * sin(now * 23)
        var strained = state
        strained.y *= 1 + strain * Float(0.7 * tug + tremble)
        if strained.x < 1 { strained.x = min(strained.x + strain * Float(0.025 * tug), 0.995) }
        return strained
    }
}
