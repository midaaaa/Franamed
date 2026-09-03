//
//  AppGameConfig.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct AppGameConfig: Codable, Sendable, Equatable {
    let curationGateEnabled: Bool
    let dailyFreeAttempts: Int
    let attemptsPerCorrectStreak: Int
    let curationRewardAttempts: Int
    let playlistCompletionReward: Int
    let autoHideReportWeight: Double
    let catalogCacheTTLSeconds: Int
    let onboardingMediaKey: String
}
