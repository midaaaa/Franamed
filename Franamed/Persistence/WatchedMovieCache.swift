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
    #Unique<WatchedMovieCache>([\.tmdbId, \.mediaTypeRawValue])
    var tmdbId: Int
    var mediaTypeRawValue: String = MediaType.movie.rawValue
    var addedAt: Date

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRawValue) ?? .movie }
        set { mediaTypeRawValue = newValue.rawValue }
    }

    init(tmdbId: Int, mediaType: MediaType, addedAt: Date) {
        self.tmdbId = tmdbId
        self.mediaTypeRawValue = mediaType.rawValue
        self.addedAt = addedAt
    }
}
