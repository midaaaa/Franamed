//
//  RoundRecord.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 20.08.2026.
//

import Foundation
import SwiftData

@Model
final class RoundRecord {
    var id: UUID
    var tmdbId: Int
    var mediaType: MediaType = MediaType.movie
    var playedAt: Date
    var attemptsUsed: Int
    var wasCorrect: Bool
    var guessedTitle: String?
    var isDaily: Bool
    var dailyDate: String?

    init(
        id: UUID = UUID(),
        tmdbId: Int,
        mediaType: MediaType,
        playedAt: Date,
        attemptsUsed: Int,
        wasCorrect: Bool,
        guessedTitle: String? = nil,
        isDaily: Bool,
        dailyDate: String? = nil
    ) {
        self.id = id
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.playedAt = playedAt
        self.attemptsUsed = attemptsUsed
        self.wasCorrect = wasCorrect
        self.guessedTitle = guessedTitle
        self.isDaily = isDaily
        self.dailyDate = dailyDate
    }
}
