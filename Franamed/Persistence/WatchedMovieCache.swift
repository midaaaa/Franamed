//
//  WatchedMovieCache.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 20.08.2026.
//

import Foundation
import SwiftData

@Model
final class WatchedMovieCache {
    #Unique<WatchedMovieCache>([\.tmdbId])
    var tmdbId: Int
    var addedAt: Date

    init(tmdbId: Int, addedAt: Date) {
        self.tmdbId = tmdbId
        self.addedAt = addedAt
    }
}
