//
//  RoundFinish.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

struct RoundFinish: Decodable, Sendable {
    struct Stats: Decodable, Sendable {
        let players: Int
        let solvedAtFrame: [Int]
    }

    let watched: WatchedEntry
    let stats: Stats?
}
