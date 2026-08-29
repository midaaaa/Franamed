//
//  PixelGrid.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct PixelGrid {
    let scale: CGFloat

    init(displayScale: CGFloat) {
        scale = max(displayScale, 1)
    }

    func snapped(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    func snapped(_ size: CGSize) -> CGSize {
        CGSize(width: snapped(size.width), height: snapped(size.height))
    }

    func evenAligned(_ value: CGFloat, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGFloat {
        (value * scale / 2).rounded(rule) * 2 / scale
    }
}
