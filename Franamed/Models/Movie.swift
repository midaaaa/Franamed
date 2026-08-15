//
//  Movie.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

struct Movie: Codable, Identifiable {
    let id: Int
    let title: String
    let releaseDate: String?
    let overview: String?
    let originalTitle: String
}
