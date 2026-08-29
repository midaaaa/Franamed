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
}

