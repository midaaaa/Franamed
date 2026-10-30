//
//  PosterFinish.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import Foundation

enum PosterFinish: Int {
    case holo = 1
    case rainbow = 2
    case diamond = 3
    case hiddenGold = 4

    static func forMode(_ mode: TicketGameMode) -> PosterFinish {
        switch mode {
        case .curated: .diamond
        case .collection: .hiddenGold
        default: .holo
        }
    }

    static let playlist = PosterFinish.rainbow
}
