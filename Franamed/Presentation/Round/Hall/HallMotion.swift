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
    private var rest: simd_quatd?
    private var smoothed: SIMD2<Double> = .zero

    private static let range = 0.3
    private static let restDrift = 0.006
    private static let smoothing = 0.2
    private static let reach = SIMD2<Float>(0.05, 0.03)

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let q = motion?.attitude.quaternion else { return }
            let attitude = simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w)
            MainActor.assumeIsolated { self?.consume(attitude) }
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

    private func consume(_ attitude: simd_quatd) {
        let rest = self.rest.map { simd_slerp($0, attitude, Self.restDrift) } ?? attitude
        self.rest = rest
        let turn = Self.rotationVector(rest.inverse * attitude)
        let target = simd_clamp(SIMD2(turn.y, -turn.x) / Self.range, SIMD2(repeating: -1), SIMD2(repeating: 1))
        smoothed += (target - smoothed) * Self.smoothing

        let next = SIMD2<Float>(smoothed) * Self.reach
        if simd_length(next - sway) > threshold { deliver(next) }
    }

    private static func rotationVector(_ q: simd_quatd) -> SIMD3<Double> {
        let q = q.real < 0 ? -q.normalized : q.normalized
        return 2 * q.imag
    }
}
