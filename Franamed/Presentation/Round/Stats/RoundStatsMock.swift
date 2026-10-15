//
//  RoundStatsMock.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import Foundation

enum RoundStatsMock {
    private struct Variant {
        let players: Int
        let weights: [Double]
    }

    private static let variants: [Variant] = [
        Variant(players: 1, weights: [0, 1, 0, 0, 0, 0, 0]),
        Variant(players: 7, weights: [2, 1, 1, 0, 0, 0, 3]),
        Variant(players: 10, weights: [3, 2, 1, 1, 0, 0, 3]),
        Variant(players: 1_204, weights: [52, 21, 10, 6, 3, 2, 6]),
        Variant(players: 3_870, weights: [8, 14, 22, 19, 12, 8, 17]),
        Variant(players: 512, weights: [2, 4, 6, 8, 10, 12, 58]),
        Variant(players: 96, weights: [14, 14, 14, 14, 14, 14, 16]),
        Variant(players: 2_140, weights: [30, 6, 5, 8, 22, 9, 20]),
        Variant(players: 48_310, weights: [92, 4, 2, 1, 0.6, 0.2, 0.2]),
        Variant(players: 25, weights: [0, 0, 0, 0, 0, 0, 1]),
        Variant(players: 25_400, weights: [0.4, 1.6, 4, 9, 16, 21, 48]),
    ]

    @MainActor private static var cursor = 0

    @MainActor
    static func next(itemID: Int) -> RoundStats {
        let variant = variants[cursor % variants.count]
        cursor += 1
        return make(variant, itemID: itemID)
    }

    private static func make(_ variant: Variant, itemID: Int) -> RoundStats {
        var seed = UInt64(truncatingIfNeeded: itemID) &* 0x9E37_79B9_7F4A_7C15 | 1
        let jittered = variant.weights.map { weight -> Double in
            guard weight > 0 else { return 0 }
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            let unit = Double(seed % 1_000) / 1_000
            return weight * (0.85 + unit * 0.3)
        }
        let total = jittered.reduce(0, +)
        var counts = jittered.map { total > 0 ? Int(($0 / total * Double(variant.players)).rounded()) : 0 }
        let drift = variant.players - counts.reduce(0, +)
        if let largest = counts.indices.max(by: { counts[$0] < counts[$1] }) {
            counts[largest] = max(0, counts[largest] + drift)
        }
        return RoundStats(players: variant.players,
                          solvedAtFrame: Array(counts.prefix(6)), lost: counts[6])
    }
}
