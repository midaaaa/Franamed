//
//  DailyHistoryEntry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct DailyHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    let date: String
    let mediaKey: String
    let wasCorrect: Bool
    let attemptsUsed: Int
    let completedAt: Double

    var id: String { date }
}
