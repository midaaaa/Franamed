//
//  DailyStatus.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct DailyStatus: Codable, Sendable {
    let today: String
    let playedToday: Bool
    let dailyStreak: Int
    let longestStreak: Int
    let history: [DailyHistoryEntry]
}
