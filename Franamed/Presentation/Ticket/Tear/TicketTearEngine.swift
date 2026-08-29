//
//  TicketTearEngine.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import SwiftUI

// MARK: - Render snapshot

// MARK: - Engine

@MainActor
final class TicketTearEngine {

    var config: TicketTearConfig
    private var size: CGSize = .zero

    private var nextTabStart: CGFloat { config.perfEndInset + CGFloat(brokenTabs) * geometry.pitch }
    private var frontFloor: CGFloat {
        brokenTabs > 0 ? config.perfEndInset + CGFloat(brokenTabs - 1) * geometry.pitch + geometry.tabLen : 0
    }

    private var geometry: TearGeometry {
        TearGeometry(config: config, size: size, fromStart: fromStart)
    }

    private var brokenTabs = 0
    private var front: CGFloat = 0
    private var shownFront: CGFloat = 0
    private var isComplete = false

    private var detachApex: CGFloat = 0
    private var detachTheta: CGFloat = .pi / 2
    private var detachAnchor: CGPoint = .zero
    private var detachRelease: Double = 0
    private var detachFlight: Double = 1
    private var detachElapsed: Double = 0
    private var didCuePush = true

    private var strain: CGFloat = 0
    private var strainCell = -1

    private var fromStart = true
    private var dragging = false

    private var finger: CGPoint = .zero
    private var smoothedFinger: CGPoint = .zero
    private var grabAlong: CGFloat = 0
    private var grabFront: CGFloat = 0

    private var grace: TimeInterval = 0
    private var relax: Double = 1
    private var releasedFinger: CGPoint = .zero
    private var releaseFront: CGFloat = 0
    private var releaseStrain: CGFloat = 0

    private var isReturning = false
    private var returnProgress: Double = 0
    private var returnCurlTheta: CGFloat = .pi / 2

    private var lastTick: Date?

    private var isResumable: Bool { grace > 0 || relax < 1 || brokenTabs > 0 }

    private var wasResumable = false

    var onResumableChange: ((Bool) -> Void)?
    var onTabBreak: (() -> Void)?
    var onTabHeal: (() -> Void)?
    var onComplete: (() -> Void)?
    var onWake: (() -> Void)?
    var onReturnComplete: (() -> Void)?
    var onDetachPush: (() -> Void)?

    init(config: TicketTearConfig = TicketTearConfig()) {
        self.config = config
    }

    // MARK: Perforation layout

    func updateSize(_ newSize: CGSize) {
        guard newSize != size else { return }
        size = newSize
    }

    // MARK: Punched pattern, in ticket-fixed terms

    private var patternStrainCell: Int {
        guard strainCell >= 0 else { return -1 }
        let ticketFixed = fromStart ? strainCell : geometry.tabCount - 1 - strainCell
        return ticketFixed - 1
    }

    // MARK: Gesture

    @discardableResult
    func begin(at p: CGPoint) -> Bool {
        guard geometry.perfLength > 1 else { return false }
        let resumable = isResumable

        if !resumable {
            let lateral = (p - geometry.lineStart) • geometry.stubN
            let along = (p - geometry.lineStart) • geometry.axisDir
            guard lateral >= config.stubExtent - config.grabDepth, lateral <= config.stubExtent + 28 else {
                return false
            }
            if along <= config.grabDepth {
                fromStart = true
            } else if geometry.perfLength - along <= config.grabDepth {
                fromStart = false
            } else {
                return false
            }
        } else {
            let ab = geometry.inTearSpace(p)
            guard ab.y >= 0, ab.y <= config.stubExtent else { return false }
            guard ab.x >= -28, ab.x <= max(front, config.grabDepth) + 28 else { return false }
        }

        dragging = true
        grace = config.gracePeriod
        relax = 0
        finger = p
        if !resumable { smoothedFinger = p }
        lastTick = nil
        grabAlong = geometry.inTearSpace(p).x
        grabFront = front
        onWake?()
        return true
    }

    func move(to p: CGPoint) {
        guard dragging else { return }
        finger = p
    }

    func end() {
        guard dragging else { return }
        dragging = false
        guard !isComplete else { return }
        grace = config.gracePeriod
        relax = 0
        captureRelease()
    }

    func cancelTear() {
        guard !dragging, !isComplete, isResumable else { return }
        grace = 0
        captureRelease()
        onWake?()
    }

    @discardableResult
    func returnStub(force: Bool = false) -> Bool {
        guard force || isComplete, geometry.perfLength > 1 else { return false }

        isComplete = false
        dragging = false
        detachRelease = 0
        grace = 0
        fromStart = config.returnFromStart
        brokenTabs = geometry.tabCount
        front = geometry.perfLength
        shownFront = geometry.perfLength
        releaseFront = geometry.perfLength
        releaseStrain = 0
        clearStrain()

        releasedFinger = config.returnStyle == .curled ? geometry.farCorner : geometry.handle
        smoothedFinger = releasedFinger
        returnCurlTheta = currentTheta(apexA: geometry.perfLength)

        relax = 0
        isReturning = true
        returnProgress = config.returnStyle == .zip ? 1 : 0
        lastTick = nil
        onWake?()
        return true
    }

    func reset() {
        brokenTabs = 0
        front = 0
        shownFront = 0
        detachRelease = 0
        relax = 1
        grace = 0
        isComplete = false
        dragging = false
        isReturning = false
        returnProgress = 0
        clearStrain()
        onWake?()
    }

    // MARK: Simulation

    var isAnimating: Bool {
        dragging || isReturning || grace > 0 || relax < 1
            || abs(shownFront - front) > 0.05
            || (isComplete && (detachRelease < 1 || detachFlight < 1))
    }

    private var healDuration: Double {
        if isReturning { return max(config.returnZipDuration, 0.05) }
        let frac = Double(min(max(releaseFront / max(geometry.perfLength, 1), 0), 1))
        return max(config.relaxDuration * (0.4 + 0.9 * frac), 0.05)
    }

    private var detachFadeOpacity: CGFloat {
        let fade = min(max(config.detachFadeFraction, 0.001), 1)
        let start = 1 - fade
        guard detachFlight > start else { return 1 }
        return CGFloat(1 - (detachFlight - start) / fade)
    }

    private func clearStrain() {
        strain = 0
        strainCell = -1
    }

    private func captureRelease() {
        releasedFinger = smoothedFinger
        releaseFront = front
        releaseStrain = strain
    }

    private func finishAtEnd() {
        front = geometry.perfLength
        clearStrain()
    }

    func step(now: Date) {
        guard let last = lastTick else { lastTick = now; return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return }
        lastTick = now

        let clamped = min(dt, 1.0 / 20.0)

        shownFront += (front - shownFront) * CGFloat(1 - exp(-clamped / 0.05))
        if isComplete {
            detachRelease = min(1, detachRelease + clamped / 0.42)
            detachFlight = min(1, detachFlight + clamped / max(config.detachFlightDuration, 0.01))
            if !didCuePush {
                detachElapsed += clamped
                if detachElapsed >= config.detachPushDelay {
                    didCuePush = true
                    onDetachPush?()
                }
            }
        }

        if dragging {
            let k = 1 - exp(-clamped / 0.045)
            smoothedFinger = smoothedFinger + (finger - smoothedFinger) * k
            grace = config.gracePeriod
            relax = 0
            advance()
        } else if isReturning {
            stepReturn(clamped)
        } else if isComplete {
            grace = 0
            relax = 1
        } else if grace > 0 {
            grace -= clamped
            if grace <= 0 { captureRelease() }
        } else if relax < 1 {
            heal(by: clamped)
        }

        if isResumable != wasResumable {
            wasResumable = isResumable
            onResumableChange?(isResumable)
        }
    }

    private func stepReturn(_ dt: Double) {
        if returnProgress < 1 {
            returnProgress = min(1, returnProgress + dt / max(config.returnFlightDuration, 0.01))
            return
        }
        heal(by: dt)
        if relax >= 1 {
            isReturning = false
            onReturnComplete?()
        }
    }

    private func heal(by dt: Double) {
        relax = min(1, relax + dt / healDuration)
        let e = easeOutCubic(relax)
        smoothedFinger = releasedFinger + (geometry.handle - releasedFinger) * CGFloat(e)
        front = releaseFront * CGFloat(1 - e)
        strain = releaseStrain * CGFloat(1 - e)

        let reached = front - config.perfEndInset
        let stillBroken = reached < 0 ? 0 : Int((reached / max(geometry.pitch, 0.01)).rounded(.down)) + 1
        if stillBroken < brokenTabs {
            brokenTabs = stillBroken
            onTabHeal?()
        }
        if relax >= 1 {
            brokenTabs = 0
            clearStrain()
        }
    }

    private func advance() {
        let target = grabFront + (geometry.inTearSpace(smoothedFinger).x - grabAlong) * config.tearGain

        if brokenTabs >= geometry.tabCount {
            finishAtEnd()
            return
        }

        for _ in 0..<64 {
            let next = nextTabStart
            if target <= next {
                front = max(frontFloor, min(target, next))
                clearStrain()
                return
            }

            let allowance = max(1, min(geometry.pitch * max(config.breakStretch, 0.05),
                                        geometry.perfLength - next))
            let over = target - next

            if over >= allowance {
                brokenTabs += 1
                onTabBreak?()
                if brokenTabs >= geometry.tabCount {
                    finishAtEnd()
                    if !isComplete { detach() }
                    return
                }
                continue
            }

            strainCell = brokenTabs
            strain = min(1, over / allowance)
            let creep = geometry.tabLen * config.creepFraction
            front = next + creep * (1 - exp(-over / (allowance * max(config.stretchScale, 0.02))))
            return
        }
    }

    private func detach() {
        isComplete = true
        detachApex = shownFront
        detachTheta = currentTheta(apexA: shownFront)
        detachAnchor = smoothedFinger
        detachRelease = 0
        detachFlight = 0
        detachElapsed = 0
        didCuePush = false
        onComplete?()
    }

    // MARK: Fold geometry

    func currentPose() -> TearPose {
        var apexA = shownFront
        var theta = currentTheta(apexA: shownFront)
        var offset = CGVector(dx: 0, dy: 0)
        var opacity: CGFloat = 1

        if isReturning, returnProgress < 1 {
            let e = CGFloat(easeInOutCubic(returnProgress))
            apexA = geometry.perfLength
            theta = .pi / 2 + (returnCurlTheta - .pi / 2) * e
            offset = geometry.stubN * (geometry.returnDistance * (1 - e))
            opacity = min(1, CGFloat(returnProgress / max(config.returnFadeFraction, 0.001)))
        } else if isComplete {
            let e = CGFloat(easeOutCubic(detachRelease))
            apexA = detachApex
            theta = detachTheta + (.pi / 2 - detachTheta) * e
            let flight = CGFloat(easeOutCubic(detachFlight))
            offset = smoothedFinger - detachAnchor + geometry.perfDir * (geometry.detachDistance * flight)
            opacity = detachFadeOpacity
        }

        return TearPose(perfOrigin: geometry.perfOrigin,
                        perfDir: geometry.perfDir,
                        stubN: geometry.stubN,
                        perfLength: geometry.perfLength,
                        theta: theta,
                        apexA: apexA,
                        offset: offset,
                        front: isComplete ? geometry.perfLength : shownFront,
                        pitch: geometry.pitch,
                        holeLen: geometry.holeLen,
                        patternOrigin: geometry.patternOrigin,
                        patternSign: geometry.patternSign,
                        patternInset: geometry.patternInset,
                        strainCell: patternStrainCell,
                        strain: strain,
                        opacity: opacity)
    }

    private func currentTheta(apexA: CGFloat) -> CGFloat {
        let cornerR = hypot(apexA, config.stubExtent)
        guard cornerR > 0.5 else { return .pi / 2 }
        let apex = geometry.perfOrigin + geometry.perfDir * apexA
        let v = smoothedFinger - apex
        return Self.solveTheta(cornerR: cornerR,
                                cornerPhi: atan2(config.stubExtent, -apexA),
                                reach: min(hypot(v.dx, v.dy), cornerR),
                                floor: config.tightestCurl * .pi / 180)
    }

    nonisolated private static func coneRuling(beta: CGFloat, theta: CGFloat) -> SIMD3<Double> {
        let st = sin(theta), ct = cos(theta)
        return SIMD3(Double(ct * ct + st * st * cos(beta)),
                     Double(st * sin(beta)),
                     Double(st * ct * (1 - cos(beta))))
    }

    nonisolated private static func cornerReach(cornerR: CGFloat, cornerPhi: CGFloat,
                                                theta: CGFloat) -> CGFloat {
        let e = coneRuling(beta: cornerPhi / sin(theta), theta: theta)
        return cornerR * CGFloat((e.x * e.x + e.y * e.y).squareRoot())
    }

    nonisolated private static func halfTurnTheta(cornerPhi: CGFloat) -> CGFloat {
        asin(min(max(cornerPhi / .pi, 0), 1))
    }

    nonisolated private static func solveTheta(cornerR: CGFloat, cornerPhi: CGFloat,
                                       reach: CGFloat, floor: CGFloat) -> CGFloat {
        let flat = CGFloat.pi / 2
        var lo = max(floor, halfTurnTheta(cornerPhi: cornerPhi))
        var hi = flat
        guard lo < hi - 1e-4 else { return min(lo, flat) }
        guard reach < cornerReach(cornerR: cornerR, cornerPhi: cornerPhi, theta: flat) - 0.01 else {
            return flat
        }
        if cornerReach(cornerR: cornerR, cornerPhi: cornerPhi, theta: lo) > reach { return lo }
        for _ in 0..<28 {
            let mid = 0.5 * (lo + hi)
            if cornerReach(cornerR: cornerR, cornerPhi: cornerPhi, theta: mid) > reach {
                hi = mid
            } else {
                lo = mid
            }
        }
        return 0.5 * (lo + hi)
    }
}
