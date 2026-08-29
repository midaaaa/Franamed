//
//  TearFrameRateProbe.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import Foundation
import QuartzCore

@MainActor
@Observable
final class TearFrameRateProbe {

    private(set) var worstFPS: Double = 0
    private(set) var averageFPS: Double = 0
    private(set) var worstCPU: Double = 0
    private(set) var worstWait: Double = 0
    private(set) var worstGPU: Double = 0

    private(set) var sessionWorstFPS: Double = 0
    private(set) var sessionAverageFPS: Double = 0
    private(set) var sessionWorstCPU: Double = 0
    private(set) var sessionWorstWait: Double = 0
    private(set) var sessionWorstGPU: Double = 0

    private(set) var isIdle = true

    @ObservationIgnored private var window = Worst()
    @ObservationIgnored private var session = Worst()
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var framesInSession = 0
    @ObservationIgnored private var windowSum: Double = 0
    @ObservationIgnored private var windowCount = 0
    @ObservationIgnored private var sessionSum: Double = 0
    @ObservationIgnored private var sessionCount = 0

    private let warmUpFrames = 5

    private let publishInterval: CFTimeInterval = 0.2

    private struct Worst {
        var frame: Double = 0
        var cpu: Double = 0
        var wait: Double = 0
        var gpu: Double = 0

        mutating func reset() { self = Worst() }
    }

    func record(frameDuration: Double, cpu: Double, wait: Double, at now: CFTimeInterval) {
        if isIdle { beginSession(at: now) }

        framesInSession += 1
        windowSum += frameDuration
        windowCount += 1
        window.frame = max(window.frame, frameDuration)
        window.cpu = max(window.cpu, cpu)
        window.wait = max(window.wait, wait)

        if framesInSession > warmUpFrames {
            sessionSum += frameDuration
            sessionCount += 1
            session.frame = max(session.frame, frameDuration)
            session.cpu = max(session.cpu, cpu)
            session.wait = max(session.wait, wait)
        }

        guard now - windowStart >= publishInterval else { return }
        windowStart = now
        flush()
    }

    func record(gpu: Double) {
        window.gpu = max(window.gpu, gpu)
        if framesInSession > warmUpFrames { session.gpu = max(session.gpu, gpu) }
    }

    func park() {
        guard !isIdle else { return }
        flush()
        window.reset()
        worstFPS = 0
        averageFPS = 0
        worstCPU = 0
        worstWait = 0
        worstGPU = 0
        isIdle = true
    }

    private func beginSession(at now: CFTimeInterval) {
        session.reset()
        window.reset()
        sessionWorstFPS = 0
        sessionAverageFPS = 0
        sessionWorstCPU = 0
        sessionWorstWait = 0
        sessionWorstGPU = 0
        windowStart = now
        framesInSession = 0
        windowSum = 0
        windowCount = 0
        sessionSum = 0
        sessionCount = 0
        isIdle = false
    }

    private func flush() {
        if window.frame > 0 { worstFPS = (1 / window.frame).rounded() }
        if windowSum > 0 { averageFPS = (Double(windowCount) / windowSum).rounded() }
        if window.cpu > 0 { worstCPU = window.cpu * 1000 }
        if window.wait > 0 { worstWait = window.wait * 1000 }
        if window.gpu > 0 { worstGPU = window.gpu * 1000 }

        if session.frame > 0 { sessionWorstFPS = (1 / session.frame).rounded() }
        if sessionSum > 0 { sessionAverageFPS = (Double(sessionCount) / sessionSum).rounded() }
        if session.cpu > 0 { sessionWorstCPU = session.cpu * 1000 }
        if session.wait > 0 { sessionWorstWait = session.wait * 1000 }
        if session.gpu > 0 { sessionWorstGPU = session.gpu * 1000 }

        window.reset()
        windowSum = 0
        windowCount = 0
    }
}
