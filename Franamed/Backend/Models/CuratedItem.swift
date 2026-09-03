//
//  CuratedItem.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CuratedItem: Codable, Sendable, Identifiable, Equatable {
    let key: String
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let originalTitle: String
    let releaseYear: Int?
    let originalLanguage: String?
    let popularity: Double
    let posterURL: String?
    let status: String
    let genreIds: [Int]
    let totalImages: Int
    let reviewedImages: Int
    let approvedImages: Int
    let adminFinalized: Bool
    let finalizedAt: Double?
    let lastSyncedAt: Double?

    var id: String { key }

    var asMediaItem: MediaItem {
        MediaItem(
            id: tmdbId,
            mediaType: mediaType,
            title: title,
            originalTitle: originalTitle,
            releaseDate: releaseYear.map { "\($0)" },
            overview: nil
        )
    }
}
