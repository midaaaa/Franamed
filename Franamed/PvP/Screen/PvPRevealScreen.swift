//
//  PvPRevealScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Reveal

struct PvPRevealScreen: Sendable, Equatable {
    let title: String
    let answer: PvPAnswerCard
    let verdict: String
    let isSolved: Bool
    let results: [PvPResultRow]
    let standings: [PvPStandingRow]
    let duel: PvPDuelBars?
    let damageLine: String?
    let next: String?
    let nextTimer: PvPTimer?
    let film: Int
    let source: PvPAnswer
    let solvedAtFrame: Int?
    let board: [PvPBoardRow]
    let clash: PvPDuelClash?
}

/// One line of the room results on the hall screen: before and after this film.
struct PvPBoardRow: Sendable, Equatable, Identifiable {
    let uid: String
    let name: String
    let avatar: PvPAvatar
    let isYou: Bool
    let gained: Int
    let isSolved: Bool
    let detail: String
    let before: Int
    let after: Int
    let placeBefore: Int
    let placeAfter: Int

    var id: String { uid }
}

/// Duel results on the hall screen: both scores collide, the difference hits the loser.
struct PvPDuelClash: Sendable, Equatable {
    struct Side: Sendable, Equatable {
        let uid: String
        let name: String
        let avatar: PvPAvatar
        let isYou: Bool
        let points: Int
        let detail: String
        let hpBefore: Int
        let hpAfter: Int
    }

    let you: Side
    let rival: Side
    let maxHP: Int
    let damage: Int
    let multiplier: Double
}

struct PvPAnswerCard: Sendable, Equatable {
    let title: String
    let subtitle: String?
    let posterPath: String?
}

struct PvPResultRow: Sendable, Equatable, Identifiable {
    let uid: String
    let name: String
    let avatar: PvPAvatar
    let isYou: Bool
    let detail: String
    let points: String
    let isSolved: Bool

    var id: String { uid }
}

// MARK: - Builder

extension PvPScreenBuilder {
    func reveal(_ reveal: PvPMatchReveal) -> PvPRevealScreen {
        let mine = reveal.results.first { $0.uid == state.you }
        let solvedAt = mine?.solvedAtFrame
        let verdict: String
        if let solvedAt, let mine {
            verdict = "Вы угадали на \(PvPScreenText.ordinal(solvedAt)) кадре · \(PvPScreenText.signed(mine.points))"
        } else if mine == nil {
            verdict = "Вы не играли этот фильм"
        } else {
            verdict = "Вы не угадали"
        }
        let bars = duelBars(damage: reveal.duel?.damage)
        return PvPRevealScreen(
            title: filmTitle(number: reveal.film, total: state.settings?.films),
            answer: answerCard(reveal.answer),
            verdict: verdict,
            isSolved: solvedAt != nil,
            results: resultRows(reveal.results),
            standings: state.kind == .room ? standingRows(reveal.standings) : [],
            duel: bars,
            damageLine: damageLine(reveal.duel),
            next: reveal.nextAt == nil ? nil : "Следующий фильм",
            nextTimer: reveal.nextAt.map { revealTimer(until: $0) },
            film: reveal.film,
            source: reveal.answer,
            solvedAtFrame: solvedAt,
            board: state.kind == .room ? boardRows(reveal) : [],
            clash: state.kind == .duel ? clash(reveal) : nil
        )
    }

    private func resultDetail(_ result: PvPFilmResult?) -> String {
        guard let result else { return "не играл" }
        guard let frame = result.solvedAtFrame else { return "не угадал" }
        return ["кадр \(frame)", result.ms.map { PvPScreenText.seconds(milliseconds: $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func boardRows(_ reveal: PvPMatchReveal) -> [PvPBoardRow] {
        let results = Dictionary(reveal.results.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = reveal.standings.map { standing -> (PvPStanding, Int, Int) in
            let result = results[standing.uid]
            let gained = result?.solvedAtFrame == nil ? 0 : result?.points ?? 0
            let after = standing.total ?? 0
            return (standing, gained, after - gained)
        }
        let beforeOrder = entries.enumerated().sorted { lhs, rhs in
            if lhs.element.2 != rhs.element.2 { return lhs.element.2 > rhs.element.2 }
            return lhs.offset < rhs.offset
        }
        var placeBefore: [String: Int] = [:]
        for (index, entry) in beforeOrder.enumerated() { placeBefore[entry.element.0.uid] = index + 1 }
        return entries.map { standing, gained, before in
            let player = state.player(standing.uid)
            return PvPBoardRow(uid: standing.uid, name: player.map(displayName) ?? "Игрок",
                               avatar: PvPAvatar(icon: player?.icon ?? "", color: player?.color ?? ""),
                               isYou: standing.uid == state.you, gained: gained,
                               isSolved: results[standing.uid]?.solvedAtFrame != nil,
                               detail: resultDetail(results[standing.uid]), before: before, after: standing.total ?? 0,
                               placeBefore: placeBefore[standing.uid] ?? standing.place, placeAfter: standing.place)
        }
    }

    private func clash(_ reveal: PvPMatchReveal) -> PvPDuelClash? {
        guard let me = state.me, let rival = state.opponents.first(where: { !$0.left }) ?? state.opponents.first else { return nil }
        let maxHP = state.duel?.maxHP ?? 1
        func side(_ player: PvPMatchPlayer) -> PvPDuelClash.Side {
            let result = reveal.results.first { $0.uid == player.uid }
            let hit = reveal.duel?.damage[player.uid] ?? 0
            let after = reveal.duel?.hp[player.uid] ?? state.duel?.hp[player.uid] ?? maxHP
            return PvPDuelClash.Side(uid: player.uid, name: displayName(player), avatar: PvPAvatar(icon: player.icon, color: player.color),
                                     isYou: player.isYou, points: result?.solvedAtFrame == nil ? 0 : result?.points ?? 0,
                                     detail: resultDetail(result), hpBefore: min(maxHP, after + hit), hpAfter: after)
        }
        let damage = reveal.duel?.damage.values.max() ?? 0
        return PvPDuelClash(you: side(me), rival: side(rival), maxHP: maxHP, damage: damage,
                            multiplier: reveal.duel?.multiplier ?? 1)
    }

    func answerCard(_ answer: PvPAnswer) -> PvPAnswerCard {
        let original = answer.originalTitle != answer.title ? answer.originalTitle : nil
        let subtitle = [original, answer.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        return PvPAnswerCard(title: answer.title, subtitle: subtitle.isEmpty ? nil : subtitle, posterPath: answer.posterPath)
    }

    private func revealTimer(until next: Date) -> PvPTimer {
        let remaining = state.pause?.remaining ?? next.timeIntervalSince(now)
        return PvPTimer(text: PvPScreenText.clock(remaining), fraction: min(1, max(0, remaining / 8)),
                        isUrgent: false, isFrozen: state.pause != nil)
    }

    func resultRows(_ results: [PvPFilmResult]) -> [PvPResultRow] {
        let ordered = results.enumerated().sorted { lhs, rhs in
            if lhs.element.points != rhs.element.points { return lhs.element.points > rhs.element.points }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return ordered.map { result in
            let player = state.player(result.uid)
            let detail: String
            if let frame = result.solvedAtFrame {
                detail = ["кадр \(frame)", result.ms.map { PvPScreenText.seconds(milliseconds: $0) }]
                    .compactMap { $0 }.joined(separator: " · ")
            } else {
                detail = "Не угадал"
            }
            return PvPResultRow(uid: result.uid, name: player.map(displayName) ?? "Игрок",
                                avatar: PvPAvatar(icon: player?.icon ?? "", color: player?.color ?? ""),
                                isYou: result.uid == state.you, detail: detail,
                                points: result.solvedAtFrame == nil ? "0" : PvPScreenText.signed(result.points),
                                isSolved: result.solvedAtFrame != nil)
        }
    }

    func standingRows(_ standings: [PvPStanding], names: [String: PvPResultPlayer] = [:]) -> [PvPStandingRow] {
        let duel = state.kind == .duel
        let ordered = standings.enumerated().sorted { lhs, rhs in
            if lhs.element.place != rhs.element.place { return lhs.element.place < rhs.element.place }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let places = Dictionary(grouping: ordered, by: \.place).mapValues(\.count)
        return ordered.map { standing in
            let player = state.player(standing.uid)
            let saved = names[standing.uid]
            let name = player.map(displayName) ?? saved.map { options.hiddenNames.contains($0.uid) ? "Скрыт" : $0.name } ?? "Игрок"
            let score = duel ? "\(PvPScreenText.number(max(0, standing.hp ?? 0))) HP" : PvPScreenText.number(standing.total ?? 0)
            return PvPStandingRow(uid: standing.uid, place: standing.place, isTied: (places[standing.place] ?? 0) > 1,
                                  name: name, avatar: PvPAvatar(icon: player?.icon ?? saved?.icon ?? "", color: player?.color ?? saved?.color ?? ""),
                                  isYou: standing.uid == state.you, score: score,
                                  detail: player?.left == true ? "вышел" : nil, isOut: player?.left == true)
        }
    }

    private func damageLine(_ duel: PvPDuelDamage?) -> String? {
        guard let duel, let hit = duel.damage.first(where: { $0.value > 0 }) else {
            return duel == nil ? nil : "Без урона — счёт равный"
        }
        let victim = state.player(hit.key)
        let who = victim?.isYou == true ? "Вы получаете" : "\(victim.map(displayName) ?? "Соперник") получает"
        let multiplier = duel.multiplier > 1 ? " · \(PvPScreenText.multiplier(duel.multiplier))" : ""
        return "\(who) \(PvPScreenText.number(hit.value)) урона\(multiplier)"
    }
}
