//
//  PvPMatchResult.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPMatchResult: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let code: String
    let you: String
    let settings: PvPSettings
    let players: [PvPResultPlayer]
    let finished: PvPFinished
    let outcome: PvPMatchOutcome
    let savedAt: Date
}

struct PvPResultPlayer: Codable, Sendable, Equatable, Identifiable {
    let uid: String
    let name: String
    let icon: String
    let color: String

    var id: String { uid }
}

enum PvPMatchOutcome: Codable, Sendable, Equatable {
    case victory
    case defeat
    case draw
    case forfeitVictory
    case forfeitDefeat
    case abandoned
    case place(Int)
}
