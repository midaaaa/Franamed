//
//  MediaItem.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

struct MediaItem: Identifiable, Equatable {
    let id: Int
    let mediaType: MediaType
    let title: String
    let originalTitle: String
    let releaseDate: String?
    let overview: String?
}
