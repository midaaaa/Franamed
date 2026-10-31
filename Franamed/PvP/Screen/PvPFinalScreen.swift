//
//  PvPFinalScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Final

struct PvPFinalScreen: Sendable, Equatable {
    enum Tone: Sendable, Equatable {
        case win
        case loss
        case draw
        case neutral
    }

    let title: String
    let subtitle: String
    let tone: PvPFinalScreen.Tone
    let standings: [PvPStandingRow]
    let duel: PvPDuelBars?
    let films: [PvPFinalFilm]
    let solvedLine: String
    let primary: PvPAction?
    let hint: String?
    let shareText: String
}

struct PvPFinalFilm: Sendable, Equatable, Identifiable {
    let number: Int
    let answer: PvPAnswerCard
    let yourResult: String
    let isSolved: Bool
    let best: String?

    var id: Int { number }
}

// MARK: - Builder

extension PvPScreenBuilder {
    func final(_ result: PvPMatchResult) -> PvPFinalScreen {
        let names = Dictionary(result.players.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let (title, subtitle, tone) = outcomeText(result)
        let films = result.finished.films.sorted { $0.film < $1.film }.map { finalFilm($0, names: names) }
        let solved = films.filter(\.isSolved).count
        let standings = standingRows(result.finished.standings, names: names)
        return PvPFinalScreen(
            title: title,
            subtitle: subtitle,
            tone: tone,
            standings: standings,
            duel: duelBars(damage: nil),
            films: films,
            solvedLine: "Угадано \(solved) из \(films.count)",
            primary: newMatchAction(result),
            hint: newMatchHint(result),
            shareText: shareText(result, title: title, standings: standings, solved: solved, total: films.count)
        )
    }

    private func outcomeText(_ result: PvPMatchResult) -> (String, String, PvPFinalScreen.Tone) {
        let films = result.finished.films.count
        let filmsText = PvPScreenText.films(films, mediaType: result.settings.mediaType)
        switch result.outcome {
        case .victory:
            return ("Победа", result.finished.reason == .knockout ? "У соперника кончилось здоровье" : "Больше здоровья после \(filmsText)", .win)
        case .defeat:
            return ("Поражение", result.finished.reason == .knockout ? "У вас кончилось здоровье" : "У соперника больше здоровья", .loss)
        case .draw:
            return ("Ничья", "Здоровья поровну", .draw)
        case .forfeitVictory:
            return ("Победа", "Техническая: соперник пропал больше чем на минуту", .win)
        case .forfeitDefeat:
            return ("Техническое поражение", "Вы вышли из дуэли или были не в сети больше минуты", .loss)
        case .abandoned:
            return ("Матч не состоялся", "Оба игрока пропали больше чем на минуту", .neutral)
        case let .place(place):
            let players = result.finished.standings.count
            let score = result.finished.standings.first { $0.uid == result.you }?.total ?? 0
            let detail = "из \(players) · \(PvPScreenText.points(score))"
            return ("\(place)-е место", detail, place == 1 ? .win : .neutral)
        }
    }

    private func finalFilm(_ film: PvPFinishedFilm, names: [String: PvPResultPlayer]) -> PvPFinalFilm {
        let mine = film.results.first { $0.uid == state.you }
        let yourResult: String
        if let mine, let frame = mine.solvedAtFrame {
            yourResult = "кадр \(frame) · \(PvPScreenText.signed(mine.points))"
        } else {
            yourResult = mine == nil ? "Не играли" : "Не угадали"
        }
        let best = film.results.filter { $0.solvedAtFrame != nil }.max { $0.points < $1.points }
        let bestName = best.flatMap { best in
            best.uid == state.you ? "вы" : state.player(best.uid).map(displayName) ?? names[best.uid]?.name
        }
        return PvPFinalFilm(number: film.film, answer: answerCard(film.answer), yourResult: yourResult,
                            isSolved: mine?.solvedAtFrame != nil, best: bestName.map { "Лучше всех: \($0)" })
    }

    private func newMatchAction(_ result: PvPMatchResult) -> PvPAction? {
        if result.settings.kind == .room {
            return state.isHost ? PvPAction(kind: .newMatch, title: "Новый матч", isEnabled: true) : nil
        }
        let requested = options.newMatchRequestedFor == result.id
        let rivalHere = state.opponents.contains { !$0.left && $0.connection != .offline }
        return PvPAction(kind: .newMatch, title: requested ? "Ждём соперника" : "Ещё раз", isEnabled: !requested && rivalHere)
    }

    private func newMatchHint(_ result: PvPMatchResult) -> String? {
        if result.settings.kind == .room { return state.isHost ? nil : "Новый матч запускает хост" }
        guard state.opponents.contains(where: { !$0.left && $0.connection != .offline }) else { return "Соперник ушёл" }
        return "Новая дуэль начнётся, когда оба нажмут «Ещё раз»"
    }

    private func shareText(_ result: PvPMatchResult, title: String, standings: [PvPStandingRow], solved: Int, total: Int) -> String {
        let mode = result.settings.kind == .duel ? "Дуэль" : "Комната"
        let table = standings.map { "\($0.place). \($0.name) — \($0.score)" }
        let marks = result.finished.films.sorted { $0.film < $1.film }.map { film in
            film.results.first { $0.uid == result.you }?.solvedAtFrame.map { "\($0)" } ?? "✕"
        }.joined(separator: " ")
        return (["Franamed · \(mode) · \(title)"] + table + ["Угадано \(solved) из \(total): \(marks)"]).joined(separator: "\n")
    }
}
