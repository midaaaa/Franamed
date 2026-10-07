//
//  CuratedPicker.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

enum CuratedPicker {
    static func pick(
        from entries: [CatalogIndex.Entry],
        played: [String: PlayedTitle],
        shuffle: ShuffleMode
    ) -> CatalogIndex.Entry? {
        let visible = entries.filter { played[$0.key]?.isHidden != true }

        switch shuffle {
        case .random:
            return visible.randomElement()
        case .smart:
            if let fresh = visible.filter({ played[$0.key] == nil }).randomElement() {
                return fresh
            }
            return pickLongestUnplayed(from: visible, played: played)
        }
    }

    private static func pickLongestUnplayed(from entries: [CatalogIndex.Entry], played: [String: PlayedTitle]) -> CatalogIndex.Entry? {
        let newestFirst = entries.sorted { lastPlayed($0, in: played) > lastPlayed($1, in: played) }
        let resting = newestFirst.count > 1 ? max(1, newestFirst.count / 3) : 0
        let candidates = Array(newestFirst.dropFirst(resting))

        let totalWeight = candidates.count * (candidates.count + 1) / 2
        guard totalWeight > 0 else { return nil }
        var roll = Int.random(in: 0..<totalWeight)
        for (index, entry) in candidates.enumerated() {
            roll -= index + 1
            if roll < 0 { return entry }
        }
        return candidates.last
    }

    private static func lastPlayed(_ entry: CatalogIndex.Entry, in played: [String: PlayedTitle]) -> Date {
        played[entry.key]?.lastPlayedAt ?? .distantPast
    }
}
