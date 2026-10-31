//
//  PvPSendBucket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPSendBucket: Sendable {
    let capacity: Int
    let refill: Duration
    private(set) var tokens: Double
    private var updatedAt: ContinuousClock.Instant

    init(capacity: Int, refill: Duration, now: ContinuousClock.Instant) {
        self.capacity = capacity
        self.refill = refill
        self.tokens = Double(capacity)
        self.updatedAt = now
    }

    mutating func take(at now: ContinuousClock.Instant) -> Bool {
        refresh(at: now)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    mutating func delay(at now: ContinuousClock.Instant) -> Duration {
        refresh(at: now)
        guard tokens < 1 else { return .zero }
        return refill * (1 - tokens)
    }

    private mutating func refresh(at now: ContinuousClock.Instant) {
        guard now > updatedAt else { return }
        tokens = min(Double(capacity), tokens + (now - updatedAt) / refill)
        updatedAt = now
    }
}
