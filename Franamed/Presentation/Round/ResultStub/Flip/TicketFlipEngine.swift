//
//  TicketFlipEngine.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI
import Combine

@MainActor
final class TicketFlipEngine: ObservableObject {
    @Published private(set) var isFrontVisible = true

    private(set) var angle: Double = 0 {
        didSet {
            let front = cos(angle) >= 0
            if front != isFrontVisible { isFrontVisible = front }
        }
    }
    private(set) var velocity: Double = 0
    private(set) var bendVelocity: Double = 0

    private var target: Double = 0
    private(set) var isDragging = false
    private var dragOrigin: Double = 0
    private var previousAngle: Double = 0
    private var lastTick: Date?
    private let parameters = FlipParameters()
    var settlesInstantly = false

    static let edgeTapZone: CGFloat = 44

    var onWake: (() -> Void)?

    var isApproachingRest: Bool {
        !isDragging && abs(angle - target) < 20 * .pi / 180
    }

    var isAnimating: Bool {
        isDragging
            || abs(angle - target) > 0.0005
            || abs(velocity) > 0.005
            || abs(bendVelocity) > 0.01
    }

    var bend: Double {
        let raw = bendVelocity * parameters.bendGain
        return max(-parameters.bendMax, min(parameters.bendMax, raw))
    }

    // MARK: Input

    func beginDrag() {
        isDragging = true
        dragOrigin = angle
        lastTick = nil
        onWake?()
    }

    func drag(translation: CGFloat, width: CGFloat) {
        guard isDragging, width > 1 else { return }
        angle = dragOrigin + .pi * Double(translation / width)
    }

    func endDrag(releaseVelocity: CGFloat? = nil, width: CGFloat = 0) {
        guard isDragging else { return }
        isDragging = false
        if let releaseVelocity, width > 1 {
            velocity = .pi * Double(releaseVelocity / width)
        }
        let predicted = angle + velocity * parameters.projection
        target = (predicted / .pi).rounded() * .pi
        if settlesInstantly { settleImmediately() }
        onWake?()
    }

    func flip(towardsTrailing: Bool) {
        isDragging = false
        let settled = (angle / .pi).rounded() * .pi
        target = settled + (towardsTrailing ? .pi : -.pi)
        onWake?()
        if settlesInstantly { settleImmediately() }
    }

    func tapEdge(at x: CGFloat, width: CGFloat) {
        guard x < Self.edgeTapZone || x > width - Self.edgeTapZone else { return }
        flip(towardsTrailing: x > width / 2)
    }

    func settleImmediately() {
        angle = target
        velocity = 0
        bendVelocity = 0
        previousAngle = angle
        lastTick = nil
        onWake?()
    }

    func park() {
        lastTick = nil
    }

    // MARK: Simulation

    func step(now: Date) {
        guard let last = lastTick else {
            lastTick = now
            previousAngle = angle
            return
        }
        let dt = min(now.timeIntervalSince(last), 1.0 / 30.0)
        lastTick = now
        guard dt > 0 else { return }

        if isDragging {
            velocity = (angle - previousAngle) / dt
        } else {
            let stiffness = pow(2 * .pi / max(parameters.response, 0.05), 2)
            let dampingCoefficient = 4 * .pi * parameters.damping / max(parameters.response, 0.05)
            velocity += (-stiffness * (angle - target) - dampingCoefficient * velocity) * dt
            angle += velocity * dt

            if abs(angle - target) < 0.001 && abs(velocity) < 0.01 {
                angle = target
                velocity = 0
            }
        }

        bendVelocity += (velocity - bendVelocity) * (1 - exp(-dt / max(parameters.bendTau, 0.01)))
        previousAngle = angle
    }
}
