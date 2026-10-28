//
//  MediaItemWithBackdrops.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

struct MediaItemWithBackdrops: Codable {
    let item: MediaItem
    let backdrops: [Backdrop]
    var posterPath: String?
}
