//
//  TicketGameMode.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

enum TicketGameMode: Int, CaseIterable {
    case random, pvp, curated, collection

    var displayName: String {
        switch self {
        case .random: "Рандом"
        case .pvp: "PvP"
        case .curated: "Курир. рандом"
        case .collection: "Подборка"
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

    func advanced(by step: Int) -> TicketGameMode {
        let all = Self.allCases
        let index = ((rawValue + step) % all.count + all.count) % all.count
        return all[index]
    }
}
