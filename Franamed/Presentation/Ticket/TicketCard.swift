//
//  TicketCard.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import Foundation

struct TicketCard {
    let mediaType: MediaType
    let posterPath: String?
    var mode: TicketGameMode = .random
    var playlist: PlaylistTicket?
    var emptyPosters: [URL] = []

    var canTear: Bool {
        switch mode {
        case .collection: (playlist?.total ?? 0) > 0
        case .pvp: false
        default: true
        }
    }
}

