//
//  DailyResultOutcome.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct DailyResultOutcome: Codable, Sendable {
    let dailyStreak: Int
    let longestStreak: Int
    let awardedAttempts: Int
}
