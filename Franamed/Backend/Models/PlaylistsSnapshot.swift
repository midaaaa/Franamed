//
//  PlaylistsSnapshot.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.10.2026.
//

import Foundation

struct PlaylistsSnapshot: Codable, Sendable {
    struct Playlist: Codable, Sendable {
        let id: String
        let title: String
        let description: String?
        let coverImageURL: String?
        let mediaType: MediaType
        let createdAt: Double
        let orderByCurator: Bool
        let folderPosters: [String]
        let items: [Item]
    }

    struct Item: Codable, Sendable {
        let key: String
        let title: String
        let releaseYear: Int?
        let posterURL: String?
        let addedAt: Double
    }

    let version: String
    let playlists: [Playlist]
}
