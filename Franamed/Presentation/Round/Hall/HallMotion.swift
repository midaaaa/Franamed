//
//  HallMotion.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import CoreMotion
import simd

final class HallMotion: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let lock = NSLock()
    private var _threshold: Float = 0.0004
    private var _sway: SIMD2<Float> = .zero
    private var _onSway: ((SIMD2<Float>) -> Void)?
    private var rest: simd_quatd?
    private var smoothed: SIMD2<Double> = .zero

    private static let range = 0.3
    private static let restDrift = 0.006
    private static let smoothing = 0.2
    private static let reach = SIMD2<Float>(0.05, 0.03)

    var threshold: Float {
        get { lock.withLock { _threshold } }
        set { lock.withLock { _threshold = newValue } }
    }

    var sway: SIMD2<Float> { lock.withLock { _sway } }

    var onSway: ((SIMD2<Float>) -> Void)? {
        get { lock.withLock { _onSway } }
        set { lock.withLock { _onSway = newValue } }
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let q = motion?.attitude.quaternion else { return }
            self?.consume(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        queue.addOperation { [weak self] in
            guard let self else { return }
            rest = nil
            smoothed = .zero
            deliver(.zero)
        }
    }

    private func deliver(_ next: SIMD2<Float>) {
        let onSway = lock.withLock {
            _sway = next
            return _onSway
        }
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
