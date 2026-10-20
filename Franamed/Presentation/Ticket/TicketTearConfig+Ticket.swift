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
        let notchRadius = TicketStyle.notchRadius(forWidth: width)
        config.pitch = max(width - 2 * notchRadius, 1) / 9
        config.holeFraction = 18.0 / 27.0
        config.holeHalfWidth = 2.0 * TicketStyle.zoom(forWidth: width)
        config.perfEndInset = notchRadius
        config.thickness = TicketStyle.paperThickness
        config.backColor = TicketStyle.paper
        return config
    }
}
