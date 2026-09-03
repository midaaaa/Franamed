//
//  Playlist.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct Playlist: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let coverImageURL: String?
    let mediaType: MediaType
    let source: PlaylistSource
    let allowUncurated: Bool
    let published: Bool
    let createdAt: Double
    let progress: PlaylistProgress?
}
