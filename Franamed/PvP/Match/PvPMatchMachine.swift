//
//  PvPMatchMachine.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPMatchMachine: PvPMatchReducer {
    func reduce(_ state: PvPMatchState, _ event: PvPMatchEvent, now: Date) -> PvPMatchState {
        var state = state
        switch event {
        case let .transport(.message(envelope)):
            apply(envelope, to: &state, now: now)
        case let .transport(.link(mode)):
            state.link = mode
        case let .transport(.closed(closure)):
            state.phase = .closed(Self.closure(closure))
        case .tick:
            break
        case let .preparation(film, status):
            if state.preparation?.film == film { state.preparation?.status = status }
        case let .answerSent(film, frame):
            if state.film?.number == film, state.film?.yourFrame == frame, state.film?.yourStatus == .thinking {
                state.film?.answering = true
            }
        }
        advance(&state, now: now)
        return state
    }

    func nextChange(of state: PvPMatchState, now: Date) -> Date? {
        var times: [Date] = []
        if state.pause == nil {
            if state.phase == .countdown, let film = state.film { times.append(film.startsAt) }
            if state.phase == .reveal, let next = state.reveal?.nextAt { times.append(next) }
            if let resumesAt = state.film?.resumesAt { times.append(resumesAt) }
        }
        return times.filter { $0 > now }.min()
    }

    // MARK: Messages

    private func apply(_ envelope: PvPEnvelope, to state: inout PvPMatchState, now: Date) {
        if let seq = envelope.seq {
            if seq < state.snapshotSeq { return }
            state.seq = max(state.seq, seq)
        }

        switch envelope.message {
        case let .welcome(welcome):
            state.you = welcome.you.uid
            state.seq = max(state.seq, welcome.seq)
            if let snapshot = welcome.snapshot { apply(snapshot, to: &state, now: now) }
            if case .closed = state.phase { state.phase = .connecting }
            markYou(&state)
        case let .snapshot(snapshot):
            apply(snapshot, to: &state, now: now)
        case let .player(player):
            upsert(player, into: &state, now: now)
        case let .playerRemoved(uid, _):
            state.players.removeAll { $0.uid == uid }
            state.duel?.hp[uid] = nil
            rank(&state)
            state.film?.participants.removeAll { $0 == uid }
            state.film?.progress.removeAll { $0.uid == uid }
        case let .settings(settings):
            state.settings = settings
        case .loading:
            state.phase = .loading
            state.film = nil
            state.preparation = nil
            state.reveal = nil
            state.result = nil
            state.pause = nil
        case let .prepare(prepare):
            state.preparation = PvPMatchPreparation(film: prepare.film, total: prepare.total, frames: prepare.frames, spares: prepare.spares, status: .loading)
            if state.phase == .loading || state.phase == .lobby { state.phase = .ready }
        case let .countdown(film, startsInMs, timeLimitMs, participants):
            countdown(film: film, startsInMs: startsInMs, timeLimitMs: timeLimitMs, participants: participants, state: &state, now: now)
        case let .progress(film, progress):
            guard state.film?.number == film else { return }
            if let index = state.film?.progress.firstIndex(where: { $0.uid == progress.uid }) {
                state.film?.progress[index] = progress
            } else {
                state.film?.progress.append(progress)
            }
            if progress.uid == state.you, state.film?.isParticipating == true {
                state.film?.yourFrame = progress.frame
                state.film?.yourStatus = progress.status
                state.film?.answering = false
            }
        case let .guessResult(film, frame, correct):
            guard state.film?.number == film else { return }
            state.film?.lastGuess = PvPMatchGuess(frame: frame, correct: correct)
        case let .deadline(film, endsInMs):
            guard state.film?.number == film else { return }
            state.film?.endsAt = now.addingTimeInterval(Self.seconds(endsInMs))
            state.film?.deadlineCut = true
        case let .paused(paused):
            state.pause = PvPMatchPause(
                pausedAt: now,
                remaining: Self.seconds(paused.remainingMs),
                autoResumeAt: now.addingTimeInterval(Self.seconds(paused.autoResumeInMs))
            )
        case let .resumed(startsInMs):
            resume(startsInMs: startsInMs, state: &state, now: now)
        case let .reveal(reveal):
            state.reveal = PvPMatchReveal(
                film: reveal.film,
                answer: reveal.answer,
                results: reveal.results,
                standings: reveal.standings,
                duel: reveal.duel,
                nextAt: reveal.nextInMs > 0 ? now.addingTimeInterval(Self.seconds(reveal.nextInMs)) : nil
            )
            state.standings = reveal.standings
            if let damage = reveal.duel {
                state.duel?.hp = damage.hp
                state.duel?.multiplier = damage.multiplier
            }
            state.film = nil
            state.phase = .reveal
        case let .finished(finished):
            state.phase = .finished
            state.pause = nil
            state.preparation = nil
            for index in state.players.indices { state.players[index].forfeitAt = nil }
            state.standings = finished.standings
            state.result = result(of: finished, state: state, now: now)
        case let .error(code, message):
            state.notice = PvPMatchNotice(code: code, message: message, at: now)
            if code == "paused" || code == "bad_phase" || code == "not_started" { state.film?.answering = false }
        case .pong, .unknown:
            break
        }
    }

    private func apply(_ snapshot: PvPSnapshot, to state: inout PvPMatchState, now: Date) {
        let previous = state
        var next = PvPMatchState(code: snapshot.code)
        next.you = snapshot.you
        next.link = previous.link
        next.notice = previous.notice
        next.seq = max(previous.seq, snapshot.seq)
        next.snapshotSeq = snapshot.seq
        next.settings = snapshot.settings
        next.standings = snapshot.standings
        next.phase = Self.phase(snapshot.phase)
        next.players = snapshot.players.map { player(from: $0, you: snapshot.you, now: now) }

        if let film = snapshot.film {
            let timeLimit = TimeInterval(snapshot.settings.timeLimitSec)
            let startsAt = now.addingTimeInterval(Self.seconds(film.startsInMs))
            let endsAt = now.addingTimeInterval(Self.seconds(film.endsInMs))
            let same = previous.film?.number == film.index ? previous.film : nil
            let running = snapshot.phase == .playing && film.startsInMs > 0
            next.film = PvPMatchFilm(
                number: film.index,
                total: film.total,
                timeLimit: timeLimit,
                startsAt: running ? endsAt.addingTimeInterval(-timeLimit) : startsAt,
                endsAt: endsAt,
                resumesAt: running ? startsAt : nil,
                deadlineCut: same?.deadlineCut ?? false,
                participants: film.progress.map(\.uid),
                progress: film.progress,
                frames: film.frames,
                yourFrame: film.yourFrame,
                yourStatus: film.yourStatus,
                lastGuess: same?.yourFrame == film.yourFrame ? same?.lastGuess : nil,
                answering: false
            )
        }

        if let prepare = snapshot.prepare {
            let kept = previous.preparation.flatMap { $0.film == prepare.film && $0.frames == prepare.frames ? $0.status : nil }
            next.preparation = PvPMatchPreparation(
                film: prepare.film,
                total: prepare.total,
                frames: prepare.frames,
                spares: prepare.spares,
                status: prepare.ready == true ? .ready : kept ?? .loading
            )
        }

        if let reveal = snapshot.lastReveal {
            let kept = previous.reveal?.film == reveal.film ? previous.reveal?.nextAt : nil
            next.reveal = PvPMatchReveal(
                film: reveal.film,
                answer: reveal.answer,
                results: reveal.results,
                standings: reveal.standings,
                duel: reveal.duel,
                nextAt: snapshot.phase == .reveal ? kept : nil
            )
        }

        if let duel = snapshot.duel {
            next.duel = PvPMatchDuel(hp: duel.hp, maxHP: snapshot.settings.hp ?? 0, multiplier: duel.multiplier)
        } else if snapshot.settings.kind == .duel, let hp = snapshot.settings.hp {
            next.duel = PvPMatchDuel(hp: Dictionary(uniqueKeysWithValues: snapshot.players.map { ($0.uid, hp) }), maxHP: hp, multiplier: 1)
        }

        if let paused = snapshot.paused {
            next.pause = PvPMatchPause(
                pausedAt: previous.pause?.pausedAt ?? now,
                remaining: Self.seconds(paused.remainingMs),
                autoResumeAt: now.addingTimeInterval(Self.seconds(paused.autoResumeInMs))
            )
        }

        if let finished = snapshot.finished {
            next.result = result(of: finished, state: next, now: previous.result?.savedAt ?? now)
        }

        state = next
    }

    // MARK: Film

    private func countdown(film number: Int, startsInMs: Int, timeLimitMs: Int, participants: [String], state: inout PvPMatchState, now: Date) {
        let startsAt = now.addingTimeInterval(Self.seconds(startsInMs))
        let timeLimit = Self.seconds(timeLimitMs)
        let playing = state.you.map(participants.contains) ?? false
        let frames = state.preparation?.film == number ? state.preparation?.frames : nil
        let total = state.preparation?.total ?? state.film?.total ?? state.settings?.films ?? number

        state.film = PvPMatchFilm(
            number: number,
            total: total,
            timeLimit: timeLimit,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(timeLimit),
            resumesAt: nil,
            deadlineCut: false,
            participants: participants,
            progress: participants.map { PvPProgress(uid: $0, frame: 1, status: .thinking) },
            frames: playing ? frames : nil,
            yourFrame: playing && frames != nil ? 1 : nil,
            yourStatus: playing && frames != nil ? .thinking : nil,
            lastGuess: nil,
            answering: false
        )
        if state.preparation?.film == number { state.preparation = nil }
        state.phase = .countdown
    }

    private func resume(startsInMs: Int, state: inout PvPMatchState, now: Date) {
        guard let pause = state.pause else { return }
        let countdown = Self.seconds(startsInMs)
        switch state.phase {
        case .countdown:
            state.film?.startsAt.addTimeInterval(now.timeIntervalSince(pause.pausedAt) + countdown)
            state.film?.endsAt = now.addingTimeInterval(countdown + pause.remaining)
        case .playing:
            state.film?.endsAt = now.addingTimeInterval(countdown + pause.remaining)
            state.film?.resumesAt = countdown > 0 ? now.addingTimeInterval(countdown) : nil
        case .reveal:
            if let reveal = state.reveal, reveal.nextAt != nil {
                state.reveal = PvPMatchReveal(
                    film: reveal.film,
                    answer: reveal.answer,
                    results: reveal.results,
                    standings: reveal.standings,
                    duel: reveal.duel,
                    nextAt: now.addingTimeInterval(pause.remaining)
                )
            }
        default:
            break
        }
        state.pause = nil
    }

    private func advance(_ state: inout PvPMatchState, now: Date) {
        guard state.pause == nil else { return }
        if state.phase == .countdown, let film = state.film, now >= film.startsAt {
            state.phase = .playing
        }
        if state.phase == .reveal, let next = state.reveal?.nextAt, now >= next {
            state.phase = .ready
        }
        if let resumesAt = state.film?.resumesAt, now >= resumesAt {
            state.film?.resumesAt = nil
        }
    }

    // MARK: Players

    private func upsert(_ player: PvPPlayer, into state: inout PvPMatchState, now: Date) {
        let mapped = self.player(from: player, you: state.you, now: now)
        if let index = state.players.firstIndex(where: { $0.uid == player.uid }) {
            state.players[index] = mapped
        } else {
            state.players.append(mapped)
            state.players.sort { ($0.joinedAt, $0.uid) < ($1.joinedAt, $1.uid) }
            if let hp = state.settings?.hp, state.duel != nil, state.duel?.hp[player.uid] == nil {
                state.duel?.hp[player.uid] = hp
            }
            rank(&state)
        }
        if player.isHost {
            for index in state.players.indices where state.players[index].uid != player.uid {
                state.players[index].isHost = false
            }
        }
    }

    private func rank(_ state: inout PvPMatchState) {
        let duel = state.kind == .duel
        var known: [String: Int] = [:]
        for standing in state.standings {
            if let score = duel ? standing.hp : standing.total { known[standing.uid] = score }
        }
        let fallback = duel ? state.settings?.hp ?? 0 : 0
        let scores = state.players.map { player in
            (player: player, score: known[player.uid] ?? state.duel?.hp[player.uid] ?? fallback)
        }
        let ordered = scores.enumerated().sorted { ($1.element.score, $0.offset) < ($0.element.score, $1.offset) }.map(\.element)
        state.standings = ordered.map { entry in
            let place = (ordered.firstIndex { $0.score == entry.score } ?? 0) + 1
            return PvPStanding(uid: entry.player.uid, place: place, total: duel ? nil : entry.score, hp: duel ? entry.score : nil)
        }
    }

    private func player(from player: PvPPlayer, you: String?, now: Date) -> PvPMatchPlayer {
        PvPMatchPlayer(
            uid: player.uid,
            name: player.name,
            alias: player.alias,
            icon: player.icon,
            color: player.color,
            isHost: player.isHost,
            isYou: player.uid == you,
            ready: player.ready,
            connection: player.connection,
            left: player.left,
            joinedAt: player.joinedAt,
            forfeitAt: player.forfeitInMs.map { now.addingTimeInterval(Self.seconds($0)) }
        )
    }

    private func markYou(_ state: inout PvPMatchState) {
        for index in state.players.indices {
            state.players[index].isYou = state.players[index].uid == state.you
        }
    }

    // MARK: Result

    private func result(of finished: PvPFinished, state: PvPMatchState, now: Date) -> PvPMatchResult? {
        guard let settings = state.settings, let you = state.you else { return nil }
        return PvPMatchResult(
            id: "\(state.code):" + finished.films.map(\.answer.mediaKey).joined(separator: ","),
            code: state.code,
            you: you,
            settings: settings,
            players: state.players.map { PvPResultPlayer(uid: $0.uid, name: $0.name, icon: $0.icon, color: $0.color) },
            finished: finished,
            outcome: outcome(of: finished, kind: settings.kind, you: you),
            savedAt: now
        )
    }

    private func outcome(of finished: PvPFinished, kind: PvPRoomKind, you: String) -> PvPMatchOutcome {
        if kind == .room {
            return .place(finished.standings.first { $0.uid == you }?.place ?? finished.standings.count)
        }
        let won = finished.winnerUid == you
        switch finished.reason {
        case .forfeit: return won ? .forfeitVictory : .forfeitDefeat
        case .abandoned: return .abandoned
        case .draw: return .draw
        case .filmsDone, .knockout: return finished.winnerUid == nil ? .draw : won ? .victory : .defeat
        }
    }

    // MARK: Mapping

    private static func phase(_ phase: PvPPhase) -> PvPMatchPhase {
        switch phase {
        case .lobby: .lobby
        case .loading: .loading
        case .ready: .ready
        case .reveal: .reveal
        case .countdown: .countdown
        case .playing: .playing
        case .finished: .finished
        case .closed: .closed(.roomClosed)
        }
    }

    private static func closure(_ closure: PvPTransportClosure) -> PvPMatchClosure {
        switch closure {
        case .cancelled:
            return .disconnected
        case let .refused(_, code):
            return code == "kicked" ? .kicked : .refused(code: code)
        case let .socket(code, reason):
            switch PvPCloseCode(rawValue: code) {
            case .left: return .left
            case .replaced: return .replaced
            case .kicked: return .kicked
            case .roomClosed: return .roomClosed
            case .removedForFlooding: return .removedForFlooding
            case .stale, .tooManyMessages, nil: return .failed(reason ?? "\(code)")
            }
        }
    }

    private static func seconds(_ milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / 1000
    }
}
