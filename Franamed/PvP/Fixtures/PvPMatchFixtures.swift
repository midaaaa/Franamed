//
//  PvPMatchFixtures.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

#if DEBUG
import Foundation

enum PvPMatchFixtures {
    // MARK: - Building blocks

    static let you = "fixture-you"
    static let rival = "fixture-rival"
    static let third = "fixture-third"
    static let fourth = "fixture-fourth"

    static let roomCode = "420042"
    static let duelCode = "240024"

    static let roomSettings = PvPSettings(kind: .room, mediaType: .movie, films: 5, frames: 6, timeLimitSec: 30, hp: nil, maxFilms: nil, maxPlayers: 8)
    static let duelSettings = PvPSettings(kind: .duel, mediaType: .movie, films: 20, frames: 6, timeLimitSec: 30, hp: 3000, maxFilms: 20, maxPlayers: 2)

    static let frames = (1...6).map { PvPFrame(path: "/fixture-frame-\($0).jpg", width: 1920, height: 1080) }
    static let spares = (7...9).map { PvPFrame(path: "/fixture-frame-\($0).jpg", width: 1920, height: 1080) }

    static let answers = [
        PvPAnswer(mediaKey: "movie_603", tmdbId: 603, mediaType: .movie, title: "Матрица", originalTitle: "The Matrix", year: 1999, posterPath: "/fixture-poster-1.jpg"),
        PvPAnswer(mediaKey: "movie_680", tmdbId: 680, mediaType: .movie, title: "Криминальное чтиво", originalTitle: "Pulp Fiction", year: 1994, posterPath: "/fixture-poster-2.jpg"),
        PvPAnswer(mediaKey: "movie_13", tmdbId: 13, mediaType: .movie, title: "Форрест Гамп", originalTitle: "Forrest Gump", year: 1994, posterPath: nil)
    ]

    static func player(_ uid: String, _ name: String, icon: String, color: String, host: Bool = false, ready: Bool = false,
                       connection: PvPConnection = .online, forfeitIn seconds: TimeInterval? = nil) -> PvPMatchPlayer {
        PvPMatchPlayer(
            uid: uid,
            name: name,
            alias: "Hidden\(name.prefix(6))",
            icon: icon,
            color: color,
            isHost: host,
            isYou: uid == you,
            ready: ready,
            connection: connection,
            left: false,
            joinedAt: Int64([you, rival, third, fourth].firstIndex(of: uid) ?? 9),
            forfeitAt: seconds.map { Date().addingTimeInterval($0) }
        )
    }

    static func roomPlayers(host: String = you, ready: Bool = false) -> [PvPMatchPlayer] {
        [
            player(you, "NoirGaffer", icon: "popcorn", color: "red", host: host == you, ready: ready),
            player(rival, "SilentFoley", icon: "clapper", color: "blue", host: host == rival, ready: true),
            player(third, "MidnightReel", icon: "projector", color: "mint", host: host == third, ready: ready),
            player(fourth, "VelvetCameo", icon: "masks", color: "purple", host: host == fourth, connection: .away)
        ]
    }

    static func duelPlayers(rivalConnection: PvPConnection = .online, forfeitIn seconds: TimeInterval? = nil, ready: Bool = true) -> [PvPMatchPlayer] {
        [
            player(you, "NoirGaffer", icon: "popcorn", color: "red", ready: ready),
            player(rival, "SilentFoley", icon: "clapper", color: "blue", ready: true, connection: rivalConnection, forfeitIn: seconds)
        ]
    }

    static func base(_ settings: PvPSettings, players: [PvPMatchPlayer], phase: PvPMatchPhase) -> PvPMatchState {
        var state = PvPMatchState(code: settings.kind == .duel ? duelCode : roomCode)
        state.you = you
        state.phase = phase
        state.link = .socket
        state.settings = settings
        state.players = players
        state.seq = 10
        state.snapshotSeq = 1
        state.standings = players.enumerated().map { index, player in
            settings.kind == .duel
                ? PvPStanding(uid: player.uid, place: 1, total: nil, hp: settings.hp)
                : PvPStanding(uid: player.uid, place: 1, total: 0, hp: nil)
        }
        if settings.kind == .duel, let hp = settings.hp {
            state.duel = PvPMatchDuel(hp: Dictionary(uniqueKeysWithValues: players.map { ($0.uid, hp) }), maxHP: hp, multiplier: 1)
        }
        return state
    }

    static func film(number: Int = 2, total: Int = 5, startsIn: TimeInterval = -8, endsIn: TimeInterval = 22, yourFrame: Int? = 2,
                     yourStatus: PvPFilmStatus? = .thinking, progress: [PvPProgress], deadlineCut: Bool = false,
                     lastGuess: PvPMatchGuess? = nil) -> PvPMatchFilm {
        PvPMatchFilm(
            number: number,
            total: total,
            timeLimit: 30,
            startsAt: Date().addingTimeInterval(startsIn),
            endsAt: Date().addingTimeInterval(endsIn),
            resumesAt: nil,
            deadlineCut: deadlineCut,
            participants: progress.map(\.uid),
            progress: progress,
            frames: yourFrame == nil ? nil : frames,
            yourFrame: yourFrame,
            yourStatus: yourStatus,
            lastGuess: lastGuess,
            answering: false
        )
    }

    static func roomStandings(_ totals: [(String, Int)]) -> [PvPStanding] {
        let sorted = totals.sorted { $0.1 > $1.1 }
        return sorted.map { uid, total in
            PvPStanding(uid: uid, place: (sorted.firstIndex { $0.1 == total } ?? 0) + 1, total: total, hp: nil)
        }
    }

    static let roomTotals = [(rival, 1720), (you, 1650), (third, 840), (fourth, 0)]

    // MARK: - Lobby

    static var lobbyHost: PvPMatchState {
        base(roomSettings, players: roomPlayers(host: you), phase: .lobby)
    }

    static var lobbyGuest: PvPMatchState {
        base(roomSettings, players: roomPlayers(host: rival, ready: true), phase: .lobby)
    }

    static var lobbyDuel: PvPMatchState {
        var state = base(duelSettings, players: duelPlayers(ready: false), phase: .lobby)
        state.duel = nil
        return state
    }

    static var lobbyAlone: PvPMatchState {
        var state = base(roomSettings, players: [player(you, "NoirGaffer", icon: "popcorn", color: "red", host: true)], phase: .lobby)
        state.notice = PvPMatchNotice(code: "not_enough_players", message: "At least two players are needed", at: Date())
        return state
    }

    // MARK: - Getting ready

    static var loading: PvPMatchState {
        base(roomSettings, players: roomPlayers(ready: true), phase: .loading)
    }

    static var preparing: PvPMatchState {
        var state = base(roomSettings, players: roomPlayers(ready: true), phase: .ready)
        state.preparation = PvPMatchPreparation(film: 1, total: 5, frames: frames, spares: spares, status: .loading)
        return state
    }

    static var preparedWaiting: PvPMatchState {
        var state = preparing
        state.preparation?.status = .ready
        return state
    }

    static var duelPreparing: PvPMatchState {
        var state = base(duelSettings, players: duelPlayers(), phase: .ready)
        state.preparation = PvPMatchPreparation(film: 1, total: 20, frames: frames, spares: spares, status: .loading)
        return state
    }

    static var countdown: PvPMatchState {
        var state = base(roomSettings, players: roomPlayers(ready: true), phase: .countdown)
        let progress = [you, rival, third].map { PvPProgress(uid: $0, frame: 1, status: .thinking) }
        state.film = film(number: 1, startsIn: 3, endsIn: 33, yourFrame: 1, progress: progress)
        return state
    }

    // MARK: - Playing

    static var playingThinking: PvPMatchState {
        var state = base(roomSettings, players: roomPlayers(ready: true), phase: .playing)
        state.standings = roomStandings(roomTotals)
        state.film = film(progress: [
            PvPProgress(uid: you, frame: 2, status: .thinking),
            PvPProgress(uid: rival, frame: 1, status: .thinking),
            PvPProgress(uid: third, frame: 3, status: .thinking)
        ], lastGuess: PvPMatchGuess(frame: 1, correct: false))
        return state
    }

    static var playingRivalSolved: PvPMatchState {
        var state = playingThinking
        state.film?.progress[1] = PvPProgress(uid: rival, frame: 1, status: .solved)
        state.film?.endsAt = Date().addingTimeInterval(14)
        state.film?.deadlineCut = true
        return state
    }

    static var playingDeadline: PvPMatchState {
        var state = playingRivalSolved
        state.film?.endsAt = Date().addingTimeInterval(4)
        state.film?.yourFrame = 5
        state.film?.progress[0] = PvPProgress(uid: you, frame: 5, status: .thinking)
        state.film?.progress[2] = PvPProgress(uid: third, frame: 6, status: .failed)
        state.film?.lastGuess = PvPMatchGuess(frame: 4, correct: false)
        return state
    }

    static var playingAnswering: PvPMatchState {
        var state = playingThinking
        state.film?.answering = true
        return state
    }

    static var playingSolved: PvPMatchState {
        var state = playingRivalSolved
        state.film?.yourStatus = .solved
        state.film?.progress[0] = PvPProgress(uid: you, frame: 2, status: .solved)
        state.film?.lastGuess = PvPMatchGuess(frame: 2, correct: true)
        return state
    }

    static var playingSpectator: PvPMatchState {
        var state = playingThinking
        state.film?.frames = nil
        state.film?.yourFrame = nil
        state.film?.yourStatus = nil
        state.film?.participants.removeAll { $0 == you }
        state.film?.progress.removeAll { $0.uid == you }
        return state
    }

    static var duelPlaying: PvPMatchState {
        var state = base(duelSettings, players: duelPlayers(), phase: .playing)
        state.film = film(number: 5, total: 20, progress: [
            PvPProgress(uid: you, frame: 2, status: .thinking),
            PvPProgress(uid: rival, frame: 3, status: .thinking)
        ])
        state.duel = PvPMatchDuel(hp: [you: 2140, rival: 1385], maxHP: 3000, multiplier: 2)
        state.standings = [PvPStanding(uid: you, place: 1, total: nil, hp: 2140), PvPStanding(uid: rival, place: 2, total: nil, hp: 1385)]
        return state
    }

    // MARK: - Reveal

    static var revealRoom: PvPMatchState {
        var state = base(roomSettings, players: roomPlayers(ready: true), phase: .reveal)
        let standings = roomStandings(roomTotals)
        state.standings = standings
        state.reveal = PvPMatchReveal(
            film: 2,
            answer: answers[0],
            results: [
                PvPFilmResult(uid: rival, solvedAtFrame: 1, ms: 6200, points: 979),
                PvPFilmResult(uid: you, solvedAtFrame: 2, ms: 11800, points: 811),
                PvPFilmResult(uid: third, solvedAtFrame: nil, ms: nil, points: 0)
            ],
            standings: standings,
            duel: nil,
            nextAt: Date().addingTimeInterval(6)
        )
        state.preparation = PvPMatchPreparation(film: 3, total: 5, frames: frames, spares: spares, status: .ready)
        return state
    }

    static var revealDuel: PvPMatchState {
        var state = duelPlaying
        state.phase = .reveal
        state.film = nil
        state.duel = PvPMatchDuel(hp: [you: 2140, rival: 727], maxHP: 3000, multiplier: 2)
        state.standings = [PvPStanding(uid: you, place: 1, total: nil, hp: 2140), PvPStanding(uid: rival, place: 2, total: nil, hp: 727)]
        state.reveal = PvPMatchReveal(
            film: 5,
            answer: answers[1],
            results: [
                PvPFilmResult(uid: you, solvedAtFrame: 1, ms: 4100, points: 986),
                PvPFilmResult(uid: rival, solvedAtFrame: 2, ms: 9700, points: 657)
            ],
            standings: state.standings,
            duel: PvPDuelDamage(multiplier: 2, damage: [you: 0, rival: 658], hp: [you: 2140, rival: 727]),
            nextAt: Date().addingTimeInterval(6)
        )
        state.preparation = PvPMatchPreparation(film: 6, total: 20, frames: frames, spares: spares, status: .loading)
        return state
    }

    // MARK: - Interruptions

    static var paused: PvPMatchState {
        var state = playingThinking
        state.pause = PvPMatchPause(pausedAt: Date().addingTimeInterval(-12), remaining: 18, autoResumeAt: Date().addingTimeInterval(288))
        return state
    }

    static var resuming: PvPMatchState {
        var state = playingThinking
        state.film?.resumesAt = Date().addingTimeInterval(3)
        state.film?.endsAt = Date().addingTimeInterval(21)
        return state
    }

    static var rivalOffline: PvPMatchState {
        var state = duelPlaying
        state.players = duelPlayers(rivalConnection: .offline, forfeitIn: 42)
        return state
    }

    static var rivalAway: PvPMatchState {
        var state = duelPlaying
        state.players = duelPlayers(rivalConnection: .away, forfeitIn: 55)
        return state
    }

    static var polling: PvPMatchState {
        var state = playingThinking
        state.link = .polling
        return state
    }

    static var reconnecting: PvPMatchState {
        var state = duelPlaying
        state.link = .reconnecting
        return state
    }

    static var kicked: PvPMatchState {
        var state = lobbyGuest
        state.phase = .closed(.kicked)
        return state
    }

    static var roomGone: PvPMatchState {
        var state = lobbyGuest
        state.phase = .closed(.refused(code: "room_not_found"))
        return state
    }

    // MARK: - Finished

    static func finished(_ settings: PvPSettings, players: [PvPMatchPlayer], reason: PvPFinishReason, winner: String?,
                         standings: [PvPStanding], outcome: PvPMatchOutcome) -> PvPMatchState {
        var state = base(settings, players: players, phase: .finished)
        state.standings = standings
        let films = answers.enumerated().map { index, answer in
            PvPFinishedFilm(film: index + 1, answer: answer, frames: frames, results: standings.map {
                PvPFilmResult(uid: $0.uid, solvedAtFrame: index + 1, ms: 5000 + index * 1000, points: 900 - index * 150)
            })
        }
        let finished = PvPFinished(reason: reason, winnerUid: winner, standings: standings, films: films)
        state.result = PvPMatchResult(
            id: "\(state.code):" + films.map(\.answer.mediaKey).joined(separator: ","),
            code: state.code,
            you: you,
            settings: settings,
            players: players.map { PvPResultPlayer(uid: $0.uid, name: $0.name, icon: $0.icon, color: $0.color) },
            finished: finished,
            outcome: outcome,
            savedAt: Date()
        )
        if settings.kind == .duel {
            let hp = Dictionary(uniqueKeysWithValues: standings.compactMap { standing in standing.hp.map { (standing.uid, $0) } })
            state.duel = PvPMatchDuel(hp: hp, maxHP: settings.hp ?? 0, multiplier: 1.5)
        }
        return state
    }

    static var finishedVictory: PvPMatchState {
        finished(duelSettings, players: duelPlayers(), reason: .knockout, winner: you,
                 standings: [PvPStanding(uid: you, place: 1, total: nil, hp: 1210), PvPStanding(uid: rival, place: 2, total: nil, hp: 0)],
                 outcome: .victory)
    }

    static var finishedDefeat: PvPMatchState {
        finished(duelSettings, players: duelPlayers(), reason: .knockout, winner: rival,
                 standings: [PvPStanding(uid: rival, place: 1, total: nil, hp: 880), PvPStanding(uid: you, place: 2, total: nil, hp: 0)],
                 outcome: .defeat)
    }

    static var finishedForfeitVictory: PvPMatchState {
        finished(duelSettings, players: duelPlayers(rivalConnection: .offline), reason: .forfeit, winner: you,
                 standings: [PvPStanding(uid: you, place: 1, total: nil, hp: 2400), PvPStanding(uid: rival, place: 2, total: nil, hp: 2900)],
                 outcome: .forfeitVictory)
    }

    static var finishedForfeitDefeat: PvPMatchState {
        finished(duelSettings, players: duelPlayers(), reason: .forfeit, winner: rival,
                 standings: [PvPStanding(uid: rival, place: 1, total: nil, hp: 1900), PvPStanding(uid: you, place: 2, total: nil, hp: 2600)],
                 outcome: .forfeitDefeat)
    }

    static var finishedDraw: PvPMatchState {
        finished(duelSettings, players: duelPlayers(), reason: .draw, winner: nil,
                 standings: [PvPStanding(uid: you, place: 1, total: nil, hp: 1500), PvPStanding(uid: rival, place: 1, total: nil, hp: 1500)],
                 outcome: .draw)
    }

    static var finishedAbandoned: PvPMatchState {
        finished(duelSettings, players: duelPlayers(rivalConnection: .offline), reason: .abandoned, winner: nil,
                 standings: [PvPStanding(uid: you, place: 1, total: nil, hp: 3000), PvPStanding(uid: rival, place: 1, total: nil, hp: 3000)],
                 outcome: .abandoned)
    }

    static var finishedRoom: PvPMatchState {
        finished(roomSettings, players: roomPlayers(), reason: .filmsDone, winner: nil,
                 standings: roomStandings([(rival, 3920), (you, 3610), (third, 2100), (fourth, 450)]), outcome: .place(2))
    }

    static var finishedRoomWinner: PvPMatchState {
        finished(roomSettings, players: roomPlayers(), reason: .filmsDone, winner: nil,
                 standings: roomStandings([(you, 4120), (rival, 3920), (third, 2100), (fourth, 450)]), outcome: .place(1))
    }

    // MARK: - Catalogue

    static var all: [(name: String, state: PvPMatchState)] {
        [
            ("Лобби, хост", lobbyHost), ("Лобби, гость", lobbyGuest), ("Лобби дуэли", lobbyDuel), ("Лобби, один", lobbyAlone),
            ("Подбор фильмов", loading), ("Загрузка кадров", preparing), ("Ждём остальных", preparedWaiting), ("Загрузка кадров дуэли", duelPreparing), ("Отсчёт", countdown),
            ("Игра, думаю", playingThinking), ("Игра, отправляю", playingAnswering), ("Игра, соперник угадал", playingRivalSolved),
            ("Игра, дедлайн", playingDeadline), ("Игра, угадал", playingSolved), ("Игра, зритель", playingSpectator),
            ("Дуэль, игра", duelPlaying), ("Разбор комнаты", revealRoom), ("Разбор дуэли", revealDuel), ("Пауза", paused),
            ("После паузы", resuming), ("Соперник offline", rivalOffline), ("Соперник свернул", rivalAway), ("Опрос", polling),
            ("Переподключение", reconnecting), ("Кик", kicked), ("Комнаты нет", roomGone),
            ("Победа", finishedVictory), ("Поражение", finishedDefeat), ("Победа техническая", finishedForfeitVictory),
            ("Техпоражение", finishedForfeitDefeat), ("Ничья", finishedDraw), ("Оба пропали", finishedAbandoned),
            ("Итог комнаты", finishedRoom), ("Итог комнаты, первое место", finishedRoomWinner)
        ]
    }

    // MARK: - Scenarios

    static var roomScenario: [PvPPreviewSession.Step] {
        [
            .init(after: .zero) { lobbyHost },
            .init(after: .seconds(2)) { loading },
            .init(after: .seconds(1)) { preparing },
            .init(after: .seconds(1)) { countdown },
            .init(after: .seconds(3)) { playingThinking },
            .init(after: .seconds(3)) { playingRivalSolved },
            .init(after: .seconds(2)) { playingSolved },
            .init(after: .seconds(2)) { revealRoom },
            .init(after: .seconds(4)) { paused },
            .init(after: .seconds(3)) { resuming },
            .init(after: .seconds(3)) { polling },
            .init(after: .seconds(3)) { finishedRoom }
        ]
    }

    static var duelScenario: [PvPPreviewSession.Step] {
        [
            .init(after: .zero) { lobbyDuel },
            .init(after: .seconds(2)) { duelPreparing },
            .init(after: .seconds(1)) { duelPlaying },
            .init(after: .seconds(3)) { rivalAway },
            .init(after: .seconds(3)) { rivalOffline },
            .init(after: .seconds(3)) { reconnecting },
            .init(after: .seconds(2)) { revealDuel },
            .init(after: .seconds(4)) { finishedVictory }
        ]
    }
}
#endif
