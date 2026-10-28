//
//  TearEdge.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 28.10.2026.
//

import Foundation

nonisolated struct TearEdge: Hashable, Sendable {
    var shift: Float = 0
    var scale: Float = 1

    static let plain = TearEdge()

    init() {}

    init(seed: UInt64) {
        var generator = SplitMix(state: seed &+ 0x2C_1B_3C_6D_8E_7F_90_A1)
        shift = generator.unit() * 8192
        scale = 0.7 + generator.unit() * 0.8
    }
}
