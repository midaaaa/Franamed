//
//  RoundStats.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import Foundation

struct RoundStats: Equatable, Sendable {
    static let minPlayers = 10

    let players: Int
    let solvedAtFrame: [Int]
    let lost: Int

    init(players: Int, solvedAtFrame: [Int], lost: Int) {
        self.players = players
        self.solvedAtFrame = solvedAtFrame
        self.lost = lost
    }

    init(players: Int, solvedAtFrame: [Int]) {
        self.init(players: players, solvedAtFrame: solvedAtFrame, lost: max(players - solvedAtFrame.reduce(0, +), 0))
    }

    var isShown: Bool { players >= Self.minPlayers }

    func share(_ count: Int) -> Double {
        players > 0 ? Double(count) / Double(players) : 0
    }

    func missed(within frameCount: Int) -> Int {
        lost + solvedAtFrame.dropFirst(frameCount).reduce(0, +)
    }
}
