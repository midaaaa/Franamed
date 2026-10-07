//
//  CuratedRoundError.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

enum CuratedRoundError: Error, LocalizedError {
    case noMatches

    var errorDescription: String? {
        switch self {
        case .noMatches: "Под эти фильтры в каталоге ничего нет"
        }
    }
}
