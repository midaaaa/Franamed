//
//  RoundPayload.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct RoundPayload: Codable, Sendable {
    let pool: RoundPool
    let date: String?
    let playlistId: String?
    let item: CuratedItem
    let frames: [CuratedImage]

    let spareFrames: [CuratedImage]

    let position: Int?
    let playlistTotal: Int?

    func asMediaItemWithBackdrops(imageBaseURL: String) -> MediaItemWithBackdrops {
        MediaItemWithBackdrops(
            item: item.asMediaItem,
            backdrops: frames.map { $0.backdrop(imageBaseURL: imageBaseURL) }
        )
    }

    var progressText: String? {
        guard let position, let playlistTotal else { return nil }
        return "\(position) из \(playlistTotal)"
    }
}
