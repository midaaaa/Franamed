//
//  TicketGameMode.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

enum TicketGameMode: Int, CaseIterable {
    case random, curated, collection, pvp

    var displayName: String {
        switch self {
        case .random: "Наугад"
        case .pvp: "Дуэль"
        case .curated: "Сеанс"
        case .collection: "Подборки"
        }
    }

    var serialCode: String {
        switch self {
        case .random: "RND"
        case .pvp: "PVP"
        case .curated: "CUR"
        case .collection: "COL"
        }
    }

    func serial(mediaType: MediaType, frameCount: Int? = nil) -> String {
        let number = 4200 + rawValue * 137 + (mediaType == .movie ? 0 : 61)
        let parts = ["FRN", serialCode, mediaType == .movie ? "MV" : "TV", frameCount.map(String.init), String(number)]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    var hasOwnPoster: Bool { self == .random || self == .curated }

    var roundSource: RoundSource {
        switch self {
        case .curated: .curated
        case .random, .pvp, .collection: .tmdb
        }
    }

    func advanced(by step: Int) -> TicketGameMode {
        let all = Self.allCases
        let index = ((rawValue + step) % all.count + all.count) % all.count
        return all[index]
    }
}
