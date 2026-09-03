//
//  PlaylistProgress.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct PlaylistProgress: Codable, Sendable, Equatable {
    let total: Int
    let answered: Int
    let correct: Int
    let accuracy: Double?
    let timesCompleted: Int
    let completedAt: Double?

    var isComplete: Bool { total > 0 && answered >= total }
}
