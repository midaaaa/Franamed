//
//  BackendUser.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct BackendUser: Codable, Sendable, Identifiable, Equatable {
    let uid: String
    let role: UserRole
    let displayName: String?
    let isAnonymous: Bool
    let reportMultiplier: Double
    let dailyStreak: Int
    let longestStreak: Int
    let lastDailyCompletedDate: String?
    let bonusAttemptsAvailable: Int
    let attemptsUsedToday: Int
    let lastAttemptResetDate: String?

    var id: String { uid }
}
