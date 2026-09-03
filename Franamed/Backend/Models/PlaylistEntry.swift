//
//  PlaylistEntry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct PlaylistEntry: Codable, Sendable, Identifiable, Equatable {
    let key: String
    let title: String
    let releaseYear: Int?
    let posterURL: String?
    let approvedImages: Int
    let state: PlaylistEntryState
    let attemptsUsed: Int
    let wasCorrect: Bool?

    var id: String { key }
}
