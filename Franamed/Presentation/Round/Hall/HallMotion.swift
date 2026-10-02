//
//  HallMotion.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import CoreMotion
import simd

@MainActor
final class HallMotion {
    var threshold: Float = 0.0004
    var onSway: ((SIMD2<Float>) -> Void)?
    private(set) var sway: SIMD2<Float> = .zero

    private let manager = CMMotionManager()
    private var rest: SIMD2<Double>?
    private var smoothed: SIMD2<Double> = .zero

    private static let range = 0.3
    private static let restDrift = 0.006
    private static let smoothing = 0.2
    private static let reach = SIMD2<Float>(0.05, 0.03)

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let pose = SIMD2(attitude.roll, attitude.pitch)
            MainActor.assumeIsolated { self?.consume(pose) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        rest = nil
        smoothed = .zero
        deliver(.zero)
    }

    private func deliver(_ next: SIMD2<Float>) {
        sway = next
        onSway?(next)
    }

    private func consume(_ pose: SIMD2<Double>) {
        let rest = self.rest.map { $0 + (pose - $0) * Self.restDrift } ?? pose
        self.rest = rest
        let target = simd_clamp((pose - rest) / Self.range, SIMD2(repeating: -1), SIMD2(repeating: 1))
        smoothed += (target - smoothed) * Self.smoothing

        let next = SIMD2<Float>(Float(smoothed.x), Float(-smoothed.y)) * Self.reach
        if simd_length(next - sway) > threshold { deliver(next) }
    }
}
