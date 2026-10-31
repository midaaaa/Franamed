//
//  PvPMatchScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Match

struct PvPMatchScreen: Sendable, Equatable {
    enum Stage: Sendable, Equatable {
        case picking
        case preparing
        case waiting
        case countdown(Int)
        case playing
        case watching
    }

    let stage: Stage
    let title: String
    let stageText: String?
    let frames: [PvPFrameSlot]
    let shownFrame: Int?
    let viewableFrame: Int?
    let frameCaption: String?
    let timer: PvPTimer?
    let timerNote: String?
    let status: PvPYourStatus?
    let input: PvPAnswerInput
    let rivals: [PvPRivalRow]
    let duel: PvPDuelBars?
    let resumeIn: Int?
    let isProtected: Bool
}

struct PvPFrameSlot: Sendable, Equatable, Identifiable {
    let index: Int
    let path: String
    let isUnlocked: Bool

    var id: Int { index }
}

struct PvPYourStatus: Sendable, Equatable {
    enum Tone: Sendable, Equatable {
        case thinking
        case sending
        case wrong
        case solved
        case failed
        case out
    }

    let text: String
    let tone: Tone
}

struct PvPAnswerInput: Sendable, Equatable {
    let isEnabled: Bool
    let isSending: Bool
    let feedback: PvPMatchGuess?
}

struct PvPRivalRow: Sendable, Equatable, Identifiable {
    enum Tone: Sendable, Equatable {
        case thinking
        case solved
        case failed
        case out
    }

    let uid: String
    let name: String
    let avatar: PvPAvatar
    let frame: Int
    let frameCount: Int
    let status: String
    let tone: Tone
    let isAway: Bool

    var id: String { uid }
}

// MARK: - Builder

extension PvPScreenBuilder {
    func match() -> PvPMatchScreen {
        let film = state.film
        let stage = matchStage()
        let frameCount = state.settings?.frames ?? film?.frames?.count ?? 0
        let isPlaying = stage == .playing
        let yourFrame = film?.yourFrame
        let slots = (film?.frames ?? []).enumerated().map { index, frame in
            PvPFrameSlot(index: index, path: frame.path, isUnlocked: isPlaying && index < (yourFrame ?? 0))
        }
        let shown = isPlaying ? yourFrame.map { max(0, min($0, slots.count) - 1) } : nil
        let isDone = film?.yourStatus == .solved || film?.yourStatus == .failed
        let viewable = isDone && !slots.isEmpty ? slots.count - 1 : shown
        let resumeIn = film?.resumesAt.map { max(1, Int($0.timeIntervalSince(now).rounded(.up))) }
        return PvPMatchScreen(
            stage: stage,
            title: filmTitle(number: film?.number ?? state.preparation?.film ?? nextFilmNumber, total: film?.total ?? state.preparation?.total),
            stageText: stageText(stage),
            frames: slots,
            shownFrame: shown,
            viewableFrame: viewable,
            frameCaption: isPlaying ? yourFrame.map { "Кадр \(min($0, frameCount)) из \(frameCount)" } : nil,
            timer: filmTimer(stage: stage),
            timerNote: film?.deadlineCut == true && state.phase == .playing ? "Кто-то уже угадал — время урезано" : nil,
            status: yourStatus(stage: stage),
            input: answerInput(stage: stage),
            rivals: rivalRows(frameCount: frameCount),
            duel: duelBars(damage: nil),
            resumeIn: state.pause == nil ? resumeIn : nil,
            isProtected: isPlaying
        )
    }

    private var nextFilmNumber: Int {
        (state.reveal?.film ?? 0) + 1
    }

    func filmTitle(number: Int, total: Int?) -> String {
        let noun = PvPScreenText.title(state.settings?.mediaType ?? .movie)
        guard state.kind == .room, let total = total ?? state.settings?.films else { return "\(noun) \(number)" }
        return "\(noun) \(number) из \(total)"
    }

    private func matchStage() -> PvPMatchScreen.Stage {
        switch state.phase {
        case .loading:
            return .picking
        case .countdown:
            let left = state.film.map { $0.startsAt.timeIntervalSince(now) } ?? 0
            return .countdown(max(1, Int(left.rounded(.up))))
        case .playing:
            return state.film?.isParticipating == true ? .playing : .watching
        default:
            switch state.preparation?.status {
            case .loading?, .broken?: return .preparing
            case .ready?, nil: return .waiting
            }
        }
    }

    private func stageText(_ stage: PvPMatchScreen.Stage) -> String? {
        switch stage {
        case .picking:
            return "Подбираем фильмы"
        case .preparing:
            if case .broken? = state.preparation?.status { return "Кадр не загрузился — меняем на запасной" }
            return "Загружаем кадры"
        case .waiting:
            return state.preparation == nil ? "Ждём начала фильма" : "Ждём остальных"
        case .countdown:
            return state.film?.isParticipating == true ? "Приготовьтесь" : "Вы играете со следующего фильма"
        case .watching:
            return "Вы подключились посреди фильма — играете со следующего"
        case .playing:
            return nil
        }
    }

    private func filmTimer(stage: PvPMatchScreen.Stage) -> PvPTimer? {
        guard let film = state.film else { return nil }
        switch stage {
        case .countdown:
            return PvPTimer(text: PvPScreenText.clock(film.timeLimit), fraction: 1, isUrgent: false, isFrozen: true)
        case .playing, .watching:
            let frozen = state.pause != nil || film.resumesAt.map { $0 > now } == true
            let remaining: TimeInterval
            if let pause = state.pause {
                remaining = pause.remaining
            } else if let resumesAt = film.resumesAt, resumesAt > now {
                remaining = film.endsAt.timeIntervalSince(resumesAt)
            } else {
                remaining = film.endsAt.timeIntervalSince(now)
            }
            let fraction = film.timeLimit > 0 ? min(1, max(0, remaining / film.timeLimit)) : 0
            return PvPTimer(text: PvPScreenText.clock(remaining), fraction: fraction,
                            isUrgent: remaining <= 5 && !frozen, isFrozen: frozen)
        default:
            return nil
        }
    }

    private func yourStatus(stage: PvPMatchScreen.Stage) -> PvPYourStatus? {
        guard stage == .playing, let film = state.film else { return nil }
        if film.answering { return PvPYourStatus(text: "Отправляем ответ", tone: .sending) }
        switch film.yourStatus {
        case .solved?:
            let frame = film.lastGuess?.correct == true ? film.lastGuess?.frame : film.yourFrame
            return PvPYourStatus(text: "Верно! Угадали на \(PvPScreenText.ordinal(frame ?? 1)) кадре", tone: .solved)
        case .failed?:
            return PvPYourStatus(text: "Кадры кончились — ждём остальных", tone: .failed)
        case .out?:
            return PvPYourStatus(text: "Вы пропускаете этот фильм", tone: .out)
        case .thinking?, nil:
            guard let frame = film.yourFrame, frame > 1 else { return nil }
            if let guess = film.lastGuess, !guess.correct, guess.frame == frame - 1 {
                return PvPYourStatus(text: "Мимо — открыт кадр \(frame)", tone: .wrong)
            }
            return PvPYourStatus(text: "Открыт кадр \(frame)", tone: .thinking)
        }
    }

    private func answerInput(stage: PvPMatchScreen.Stage) -> PvPAnswerInput {
        let film = state.film
        let resuming = film?.resumesAt.map { $0 > now } == true
        let enabled = stage == .playing && state.pause == nil && !resuming
            && film?.yourStatus == .thinking && film?.answering == false
        return PvPAnswerInput(isEnabled: enabled, isSending: film?.answering == true, feedback: film?.lastGuess)
    }

    private func rivalRows(frameCount: Int) -> [PvPRivalRow] {
        guard let film = state.film else { return [] }
        return state.opponents.filter { !$0.left }.map { player in
            let progress = film.progress(of: player.uid)
            let frame = progress?.frame ?? 0
            let tone: PvPRivalRow.Tone
            let status: String
            switch progress?.status {
            case .solved?:
                tone = .solved
                status = "Угадал"
            case .failed?:
                tone = .failed
                status = "Не угадал"
            case .thinking?:
                tone = .thinking
                status = "Кадр \(frame) из \(frameCount)"
            case .out?, nil:
                tone = .out
                status = "Ждёт следующего фильма"
            }
            return PvPRivalRow(uid: player.uid, name: displayName(player), avatar: PvPAvatar(icon: player.icon, color: player.color),
                               frame: frame, frameCount: frameCount, status: status, tone: tone,
                               isAway: player.connection != .online)
        }
    }

    func duelBars(damage: [String: Int]?) -> PvPDuelBars? {
        guard state.kind == .duel, let duel = state.duel, let me = state.me,
              let rival = state.opponents.first(where: { !$0.left }) ?? state.opponents.first else { return nil }
        func bar(_ player: PvPMatchPlayer) -> PvPHealthBar {
            let hp = duel.hp[player.uid] ?? duel.maxHP
            let hit = damage?[player.uid].flatMap { $0 > 0 ? PvPScreenText.damage($0) : nil }
            return PvPHealthBar(uid: player.uid, name: displayName(player), avatar: PvPAvatar(icon: player.icon, color: player.color),
                                isYou: player.isYou, hp: hp, maxHP: duel.maxHP, text: PvPScreenText.number(max(0, hp)), damage: hit)
        }
        let multiplier = duel.multiplier > 1 ? "Урон \(PvPScreenText.multiplier(duel.multiplier))" : nil
        return PvPDuelBars(you: bar(me), rival: bar(rival), multiplier: multiplier)
    }
}
