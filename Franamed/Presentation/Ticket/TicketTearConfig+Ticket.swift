//
//  TicketTearConfig+Ticket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import CoreGraphics

extension TicketTearConfig {
    static func ticket(width: CGFloat) -> TicketTearConfig {
        var config = TicketTearConfig()
        config.stubSide = .bottom
        config.pitch = max(width - 2 * TicketStyle.tearNotchRadius, 1) / 9
        config.holeFraction = 18.0 / 27.0
        config.holeHalfWidth = 2.0
        config.perfEndInset = TicketStyle.tearNotchRadius
        config.thickness = TicketStyle.paperThickness
        config.backColor = TicketStyle.paper
        return config
    }
}
