//
//  PlaylistAnswers.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.10.2026.
//

import Foundation

struct PlaylistAnswers: Codable, Sendable {
    struct Answer: Codable, Sendable {
        let playlistId: String
        let mediaKey: String
        var attemptsUsed: Int
        var wasCorrect: Bool?
        var updatedAt: Double
    }

    struct Completion: Codable, Sendable {
        let playlistId: String
        var timesCompleted: Int
        var completedAt: Double?
    }

    var answers: [Answer]
    var completions: [Completion]
}
