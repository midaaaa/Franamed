//
//  FlipVelocityTracker.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import Foundation

struct FlipVelocityTracker {
    private struct Sample {
        let time: TimeInterval
        let x: CGFloat
    }

    private var samples: [Sample] = []
    private let horizon: TimeInterval = 0.12

    mutating func reset() {
        samples.removeAll()
    }

    mutating func add(time: TimeInterval, x: CGFloat) {
        samples.append(Sample(time: time, x: x))
        samples.removeAll { time - $0.time >= horizon }
    }

    func velocity(at now: TimeInterval) -> CGFloat {
        guard let last = samples.last else { return 0 }
        let current = Sample(time: max(now, last.time), x: last.x)

        var weightSum = 0.0, timeSum = 0.0, xSum = 0.0
        var points: [(weight: Double, time: Double, x: Double)] = []
        for sample in samples + [current] {
            let age = current.time - sample.time
            guard age < horizon else { continue }
            let weight = 1 - age / horizon
            let time = sample.time - current.time
            points.append((weight, time, Double(sample.x)))
            weightSum += weight
            timeSum += weight * time
            xSum += weight * Double(sample.x)
        }
        guard points.count >= 2, weightSum > 0 else { return 0 }

        let timeMean = timeSum / weightSum
        let xMean = xSum / weightSum
        var covariance = 0.0, variance = 0.0
        for point in points {
            let dt = point.time - timeMean
            covariance += point.weight * dt * (point.x - xMean)
            variance += point.weight * dt * dt
        }
        guard variance > 1e-9 else { return 0 }
        return CGFloat(covariance / variance)
    }
}
