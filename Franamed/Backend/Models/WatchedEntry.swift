//
//  WatchedEntry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct WatchedEntry: Codable, Sendable, Identifiable, Equatable {
    let mediaKey: String
    let sources: [WatchedSource]
    let addedAt: Double
    var hidden: Bool? = nil
    var plays: Int? = nil
    var lastPlayedAt: Double? = nil

    var id: String { mediaKey }

    var playedTitle: PlayedTitle? {
        let isHidden = hidden ?? false
        guard (plays ?? 0) > 0 || isHidden else { return nil }
        return PlayedTitle(
            isHidden: isHidden,
            lastPlayedAt: Date(timeIntervalSince1970: (lastPlayedAt ?? addedAt) / 1000)
        )
    }
}
