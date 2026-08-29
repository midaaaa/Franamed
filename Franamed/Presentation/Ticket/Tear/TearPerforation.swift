//
//  TearPerforation.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import CoreGraphics

nonisolated struct TearPerforation: Equatable {
    let endInset: CGFloat
    let tabCount: Int
    let pitch: CGFloat
    let holeLength: CGFloat
    let halfWidth: CGFloat
    let cornerScale: CGFloat

    init(config: TicketTearConfig, length: CGFloat) {
        endInset = config.perfEndInset
        let span = max(length - 2 * config.perfEndInset, 1)
        tabCount = max(2, Int((span / max(config.pitch, 1)).rounded()) + 1)
        pitch = span / (CGFloat(tabCount) - config.holeFraction)
        holeLength = pitch * config.holeFraction
        halfWidth = config.holeHalfWidth
        cornerScale = config.slotCorner
    }

    var tabLength: CGFloat { pitch - holeLength }

    var holeCount: Int { max(tabCount - 1, 0) }

    func holeCenter(_ index: Int) -> CGFloat {
        endInset + tabLength + CGFloat(index) * pitch + holeLength / 2
    }
}
