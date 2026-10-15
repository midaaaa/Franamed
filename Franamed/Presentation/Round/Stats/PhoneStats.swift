//
//  PhoneStats.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.10.2026.
//

import Foundation

struct PhoneStats: Equatable {
    enum Framing {
        case onlyPlayer
        case firstFrame
        case sameFrame
        case top
        case better
        case lost
    }

    struct GridLine: Hashable {
        let share: Double
        let players: Int?
    }

    struct Column: Identifiable, Equatable {
        let id: Int
        let label: String
        let share: Double
        let isMine: Bool
        let isCounted: Bool
    }

    let stats: RoundStats
    let solvedAtFrame: Int?
    let frameCount: Int
    var time = Date.now

    init(stats: RoundStats, solvedAtFrame: Int?, frameCount: Int) {
        self.stats = Self.includingYou(stats, solvedAtFrame: solvedAtFrame, frameCount: frameCount)
        self.solvedAtFrame = solvedAtFrame
        self.frameCount = frameCount
    }

    private static func includingYou(_ stats: RoundStats, solvedAtFrame: Int?, frameCount: Int) -> RoundStats {
        if let frame = solvedAtFrame {
            guard (stats.solvedAtFrame[safe: frame - 1] ?? 0) == 0 else { return stats }
            var frames = stats.solvedAtFrame
            if frames.indices.contains(frame - 1) { frames[frame - 1] += 1 }
            return RoundStats(players: stats.players + 1, solvedAtFrame: frames, lost: stats.lost)
        }
        guard stats.missed(within: frameCount) == 0 else { return stats }
        return RoundStats(players: stats.players + 1, solvedAtFrame: stats.solvedAtFrame, lost: stats.lost + 1)
    }

    var isSolved: Bool { solvedAtFrame != nil }
    var showsPercent: Bool { stats.isShown }

    var framing: Framing {
        if stats.players <= 1 { return .onlyPlayer }
        guard let frame = solvedAtFrame else { return .lost }
        if frame == 1 { return .firstFrame }
        if showsPercent && 2 * atLeastAsGood <= stats.players { return .top }
        let isWeak = later == 0 || (showsPercent && stats.share(later) < Self.weakBetterShare)
        return isWeak ? .sameFrame : .better
    }

    var heroCount: Int {
        switch framing {
        case .onlyPlayer: 1
        case .firstFrame: stats.solvedAtFrame.first ?? 0
        case .sameFrame: stats.solvedAtFrame[safe: (solvedAtFrame ?? 1) - 1] ?? 0
        case .top: atLeastAsGood
        case .better: later
        case .lost: stats.missed(within: frameCount)
        }
    }

    var heroShare: Double { stats.share(heroCount) }

    var caption: String {
        switch framing {
        case .onlyPlayer: "ИГРОКОВ"
        case .firstFrame: "С 1-ГО КАДРА"
        case .sameFrame: "С \(solvedAtFrame ?? 1)-ГО КАДРА"
        case .top: "ВЫ В ТОП"
        case .better: "ВЫ ЛУЧШЕ"
        case .lost: "НЕ УГАДАЛИ"
        }
    }

    var unit: String {
        let players = stats.players.formatted()
        switch framing {
        case .onlyPlayer:
            return "пока только вы"
        case .firstFrame, .sameFrame, .lost:
            if heroCount == 1 { return showsPercent ? "из \(players) — только вы" : "только вы" }
            return showsPercent ? "из \(players), как и вы" : "игроков, как и вы"
        case .top:
            return "из \(players) игроков"
        case .better:
            return showsPercent ? "игроков из \(players)" : "игроков"
        }
    }

    var columns: [Column] {
        let mine = solvedAtFrame.map { $0 - 1 } ?? frameCount
        let shares = (0..<frameCount).map { stats.share(stats.solvedAtFrame[safe: $0] ?? 0) }
            + [stats.share(stats.missed(within: frameCount))]
        return shares.enumerated().map { index, share in
            let isCounted = switch framing {
            case .top: index < mine
            case .better: index > mine
            case .onlyPlayer, .firstFrame, .sameFrame, .lost: false
            }
            return Column(id: index, label: index < frameCount ? "\(index + 1)" : "✕", share: share,
                          isMine: index == mine, isCounted: isCounted)
        }
    }

    var gridTop: Double {
        (peakShare / gridStep).rounded(.up) * gridStep
    }

    var gridLines: [GridLine] {
        (1...Int((gridTop / gridStep).rounded())).map { index in
            let share = Double(index) * gridStep
            return GridLine(share: share, players: showsPercent ? nil : Int((share * Double(stats.players)).rounded()))
        }
    }

    private var peakShare: Double { max(columns.map(\.share).max() ?? 0, 0.01) }

    private var gridStep: Double {
        guard showsPercent else {
            let peak = peakShare * Double(stats.players)
            return ([1.0, 2, 5].first { peak / $0 <= 3 } ?? 5) / Double(max(stats.players, 1))
        }
        return ([5.0, 10, 20, 25, 50].first { peakShare * 100 / $0 <= 3 } ?? 50) / 100
    }

    private static let weakBetterShare = 0.1

    private var later: Int {
        stats.solvedAtFrame.dropFirst(solvedAtFrame ?? 0).reduce(0, +) + stats.lost
    }

    private var atLeastAsGood: Int { stats.players - later }
}
