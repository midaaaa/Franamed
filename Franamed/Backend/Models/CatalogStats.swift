//
//  CatalogStats.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CatalogStats: Codable, Sendable {
    let items: [PerType]
    let images: [String: Int]
    let users: Int
    let playlists: Int

    struct PerType: Codable, Sendable, Identifiable {
        let mediaType: MediaType
        let total: Int
        let approved: Int
        let playable: Int
        let finalized: Int
        let withPoster: Int

        var id: String { mediaType.rawValue }

        private enum CodingKeys: String, CodingKey {
            case mediaType = "media_type"
            case total, approved, playable, finalized, withPoster
        }
    }
}
