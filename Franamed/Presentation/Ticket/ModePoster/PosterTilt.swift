//
//  PosterTilt.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import CoreMotion
import Combine
import Foundation
import os
import SwiftUI
import UIKit
import simd

@MainActor
final class PosterTilt: ObservableObject {
    static let shared = PosterTilt()

    @Published private(set) var phase: SIMD2<Float> = .zero

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let mailbox = Mailbox()
    private var users = 0
    private var isInBackground = false
    private var isRunning = false
    private var lastTimestamp: TimeInterval?
    private var previous: simd_quatd?
    private var turned: SIMD2<Double>
    private var smoothed: SIMD2<Double>
    private var observers: [NSObjectProtocol] = []

    static let lap = 2 * Double.pi / 5
    private static let rate = 30.0
    private static let phaseKey = "posterTiltPhase"
    private static let smoothingTime = 0.05
    private static let threshold: Float = 0.002

    private init() {
        let stored = UserDefaults.standard.array(forKey: Self.phaseKey) as? [Double] ?? []
        turned = stored.count == 2 ? SIMD2(stored[0], stored[1]) : .zero
        smoothed = turned
        self.phase = Self.laps(turned)
        let center = NotificationCenter.default
        let events: [(Notification.Name, @MainActor (PosterTilt) -> Void)] = [
            (UIApplication.didEnterBackgroundNotification, { $0.isInBackground = true }),
            (UIApplication.willEnterForegroundNotification, { $0.isInBackground = false }),
            (.NSProcessInfoPowerStateDidChange, { _ in }),
            (ProcessInfo.thermalStateDidChangeNotification, { _ in }),
        ]
        observers = events.map { name, change in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    change(PosterTilt.shared)
                    PosterTilt.shared.update()
                }
            }
        }
    }

    func retain() {
        users += 1
        update()
    }

    func release() {
        users = max(0, users - 1)
        update()
    }

    // MARK: Sources

    private var shouldRun: Bool {
        users > 0 && !isInBackground && !Self.savesEnergy
    }

    private static var savesEnergy: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private func update() {
        if shouldRun { start() } else { stop() }
    }

    private func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        isRunning = true
        manager.deviceMotionUpdateInterval = 1 / Self.rate
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue, withHandler: Self.handler(for: mailbox))
    }

    private func stop() {
        isRunning = false
        manager.stopDeviceMotionUpdates()
        mailbox.clear()
        lastTimestamp = nil
        guard previous != nil else { return }
        previous = nil
        turned = smoothed
        UserDefaults.standard.set([turned.x, turned.y], forKey: Self.phaseKey)
    }

    private nonisolated static func handler(for mailbox: Mailbox) -> CMDeviceMotionHandler {
        { motion, _ in
            guard let motion else { return }
            let q = motion.attitude.quaternion
            let sample = MotionSample(quaternion: SIMD4(q.x, q.y, q.z, q.w), timestamp: motion.timestamp)
            guard mailbox.put(sample) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PosterTilt.shared.drain() }
            }
        }
    }

    private func drain() {
        guard isRunning, let sample = mailbox.take() else { return }
        let dt = lastTimestamp.map { min(max(sample.timestamp - $0, 1.0 / 120), 0.1) } ?? 1 / Self.rate
        lastTimestamp = sample.timestamp
        let q = sample.quaternion
        consume(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w), orientation: Self.interfaceOrientation, dt: dt)
    }

    private func consume(_ attitude: simd_quatd, orientation: UIInterfaceOrientation, dt: Double) {
        defer { previous = attitude }
        guard let previous else { return }
        let turn = Self.screenTurn(Self.rotationVector(previous.inverse * attitude), orientation)
        turned += SIMD2(turn.y, -turn.x)
        smooth(dt: dt)
    }

    private func smooth(dt: Double) {
        smoothed += (turned - smoothed) * (1 - exp(-dt / Self.smoothingTime))
        let whole = (smoothed / Self.lap).rounded(.down)
        if whole != .zero {
            turned -= whole * Self.lap
            smoothed -= whole * Self.lap
        }
        publish(Self.laps(smoothed))
    }

    private static func laps(_ phase: SIMD2<Double>) -> SIMD2<Float> {
        let turns = phase / lap
        return SIMD2<Float>(turns - turns.rounded(.down))
    }

    private func publish(_ next: SIMD2<Float>) {
        let step = next - phase
        let wrapped = step - step.rounded(.toNearestOrAwayFromZero)
        if simd_length(wrapped) > Self.threshold { phase = next }
    }

    private static var interfaceOrientation: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    private static func screenTurn(_ turn: SIMD3<Double>, _ orientation: UIInterfaceOrientation) -> SIMD3<Double> {
        switch orientation {
        case .portraitUpsideDown: SIMD3(-turn.x, -turn.y, turn.z)
        case .landscapeLeft: SIMD3(turn.y, -turn.x, turn.z)
        case .landscapeRight: SIMD3(-turn.y, turn.x, turn.z)
        default: turn
        }
    }

    private static func rotationVector(_ q: simd_quatd) -> SIMD3<Double> {
        let q = q.real < 0 ? -q.normalized : q.normalized
        return 2 * q.imag
    }
}

private struct MotionSample: Sendable {
    let quaternion: SIMD4<Double>
    let timestamp: TimeInterval
}

private final class Mailbox: Sendable {
    private struct State {
        var sample: MotionSample?
        var isScheduled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    nonisolated func put(_ sample: MotionSample) -> Bool {
        state.withLock { state in
            state.sample = sample
            defer { state.isScheduled = true }
            return !state.isScheduled
        }
    }

    nonisolated func take() -> MotionSample? {
        state.withLock { state in
            state.isScheduled = false
            defer { state.sample = nil }
            return state.sample
        }
    }

    nonisolated func clear() {
        state.withLock { $0 = State() }
    }
}

extension EnvironmentValues {
    @Entry var posterTiltIsCovered = false
    @Entry var posterSwipeTurn: Float = 0
}

private struct PosterTiltUser: ViewModifier {
    @Environment(\.posterTiltIsCovered) private var isCovered
    @State private var isVisible = false
    @State private var isRetained = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                sync()
            }
            .onDisappear {
                isVisible = false
                sync()
            }
            .onChange(of: isCovered) { sync() }
    }

    private func sync() {
        let shouldRetain = isVisible && !isCovered
        guard shouldRetain != isRetained else { return }
        isRetained = shouldRetain
        if shouldRetain {
            PosterTilt.shared.retain()
        } else {
            PosterTilt.shared.release()
        }
    }
}

extension View {
    func posterTilt() -> some View {
        modifier(PosterTiltUser())
    }
}

private struct PosterSwipeTurn: ViewModifier, Animatable {
    var degrees: Double

    private static let gain = 3.0

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func body(content: Content) -> some View {
        let laps = degrees * .pi / 180 / PosterTilt.lap * Self.gain
        content.environment(\.posterSwipeTurn, Float(laps))
    }
}

extension View {
    func posterSwipeTurn(degrees: Double) -> some View {
        modifier(PosterSwipeTurn(degrees: degrees))
    }
}
