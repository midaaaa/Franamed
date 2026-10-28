//
//  PlaylistDetail.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct PlaylistDetail: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let coverImageURL: String?
    let mediaType: MediaType
    let createdAt: Double
    let items: [PlaylistEntry]
    var folderPosters: [String]? = nil
    var orderByCurator: Bool? = nil
}
