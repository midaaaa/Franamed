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
            nextTimer: reveal.nextAt.map { revealTimer(until: $0) }
        )
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
