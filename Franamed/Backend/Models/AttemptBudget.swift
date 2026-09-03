//
//  AttemptBudget.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct AttemptBudget: Codable, Sendable, Equatable {
    let freeAttempts: Int
    let bonusAttempts: Int
    let attemptsUsedToday: Int
    let attemptsRemaining: Int
    let gateEnabled: Bool
}
