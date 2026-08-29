//
//  MediaType.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import Foundation

enum MediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    func advanced(by step: Int) -> MediaType {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        return all[((index + step) % all.count + all.count) % all.count]
    }

    var displayName: String {
        switch self {
        case .movie: "Фильмы"
        case .tv: "Сериалы"
        }
    }

    var pluralLowercased: String {
        switch self {
        case .movie: "фильмы"
        case .tv: "сериалы"
        }
    }
}
