import Foundation
import Testing
@testable import PvPMatch

struct PvPMatchMachineTests {
    let machine = PvPMatchMachine()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func apply(_ state: PvPMatchState, _ message: PvPServerMessage, seq: Int? = nil, at seconds: TimeInterval) -> PvPMatchState {
        machine.reduce(state, .transport(.message(PvPEnvelope(seq: seq, message: message))), now: at(seconds))
    }

    static let settings = PvPSettings(kind: .room, mediaType: .movie, films: 5, frames: 6, timeLimitSec: 30, hp: nil, maxFilms: nil)
    static let frames = (1...6).map { PvPFrame(path: "/f\($0).jpg", width: 1920, height: 1080) }

    static func player(_ uid: String, host: Bool = false, joined: Int64 = 0) -> PvPPlayer {
        PvPPlayer(uid: uid, name: uid.uppercased(), alias: "Alias\(uid)", icon: "reel", color: "red", isHost: host, ready: false,
                  connection: .online, left: false, joinedAt: joined, forfeitInMs: nil)
    }

    func lobby() -> PvPMatchState {
        let snapshot = PvPSnapshot(seq: 3, phase: .lobby, code: "ABCDEF", you: "me", hostUid: "me", settings: Self.settings,
                                   players: [Self.player("me", host: true), Self.player("rival", joined: 1)], film: nil, prepare: nil,
                                   paused: nil, standings: [], lastReveal: nil, finished: nil, duel: nil)
        let welcome = PvPWelcome(seq: 3, you: .init(uid: "me", resumeToken: "pvpr1.x.y"), snapshot: snapshot)
        return apply(PvPMatchState(code: "ABCDEF"), .welcome(welcome), seq: 3, at: 0)
    }

    func playing() -> PvPMatchState {
        var state = apply(lobby(), .loading, seq: 4, at: 1)
        state = apply(state, .prepare(PvPPrepare(film: 1, total: 5, frames: Self.frames, spares: [], ready: nil)), seq: 5, at: 1)
        state = machine.reduce(state, .preparation(film: 1, .ready), now: at(2))
        state = apply(state, .countdown(film: 1, startsInMs: 3000, timeLimitMs: 30000, participants: ["me", "rival"]), seq: 6, at: 2)
        return machine.reduce(state, .tick, now: at(5))
    }

    @Test func welcomeBuildsLobby() {
        let state = lobby()
        #expect(state.phase == .lobby)
        #expect(state.isHost)
        #expect(state.me?.uid == "me")
        #expect(state.opponents.map(\.uid) == ["rival"])
    }

    @Test func countdownTurnsIntoPlayingOnTime() {
        var state = apply(lobby(), .loading, seq: 4, at: 1)
        state = apply(state, .prepare(PvPPrepare(film: 1, total: 5, frames: Self.frames, spares: [], ready: nil)), seq: 5, at: 1)
        #expect(state.phase == .ready)
        #expect(state.preparation?.status == .loading)
        state = machine.reduce(state, .preparation(film: 1, .ready), now: at(2))
        #expect(state.preparation?.status == .ready)
        state = apply(state, .countdown(film: 1, startsInMs: 3000, timeLimitMs: 30000, participants: ["me", "rival"]), seq: 6, at: 2)
        #expect(state.phase == .countdown)
        #expect(state.film?.frames == Self.frames)
        #expect(state.film?.yourFrame == 1)
        #expect(machine.nextChange(of: state, now: at(2)) == at(5))
        #expect(machine.reduce(state, .tick, now: at(4.9)).phase == .countdown)
        let started = machine.reduce(state, .tick, now: at(5))
        #expect(started.phase == .playing)
        #expect(started.film?.endsAt == at(35))
        #expect(started.film?.visibleFrames.count == 1)
    }

    @Test func spectatorGetsNoFrames() {
        var state = apply(lobby(), .loading, seq: 4, at: 1)
        state = apply(state, .countdown(film: 1, startsInMs: 3000, timeLimitMs: 30000, participants: ["rival"]), seq: 5, at: 2)
        #expect(state.film?.isParticipating == false)
        #expect(state.film?.yourFrame == nil)
    }

    @Test func guessFlowAndDeadline() {
        var state = machine.reduce(playing(), .answerSent(film: 1, frame: 1), now: at(6))
        #expect(state.film?.answering == true)
        state = apply(state, .guessResult(film: 1, frame: 1, correct: false), seq: 6, at: 6.2)
        state = apply(state, .progress(film: 1, PvPProgress(uid: "me", frame: 2, status: .thinking)), seq: 7, at: 6.2)
        #expect(state.film?.answering == false)
        #expect(state.film?.yourFrame == 2)
        #expect(state.film?.lastGuess == PvPMatchGuess(frame: 1, correct: false))

        state = apply(state, .progress(film: 1, PvPProgress(uid: "rival", frame: 1, status: .solved)), seq: 8, at: 7)
        state = apply(state, .deadline(film: 1, endsInMs: 15000), seq: 8, at: 7)
        #expect(state.film?.endsAt == at(22))
        #expect(state.film?.deadlineCut == true)
        #expect(state.film?.progress(of: "rival")?.status == .solved)
    }

    @Test func staleMessagesAfterSnapshotAreDropped() {
        let state = playing()
        let stale = apply(state, .progress(film: 1, PvPProgress(uid: "me", frame: 4, status: .thinking)), seq: 2, at: 6)
        #expect(stale == state)
        let other = apply(state, .progress(film: 2, PvPProgress(uid: "me", frame: 4, status: .thinking)), seq: 7, at: 6)
        #expect(other.film?.yourFrame == 1)
    }

    @Test func pauseFreezesAndResumeRestartsTheClock() {
        var state = apply(playing(), .paused(PvPSnapshot.Paused(remainingMs: 20000, autoResumeInMs: 300_000)), seq: 7, at: 15)
        #expect(state.pause?.remaining == 20)
        #expect(state.pause?.autoResumeAt == at(315))
        #expect(machine.nextChange(of: state, now: at(15)) == nil)

        state = apply(state, .resumed(startsInMs: 3000), seq: 8, at: 75)
        #expect(state.pause == nil)
        #expect(state.film?.resumesAt == at(78))
        #expect(state.film?.endsAt == at(98))
        #expect(machine.nextChange(of: state, now: at(75)) == at(78))
        #expect(machine.reduce(state, .tick, now: at(78)).film?.resumesAt == nil)
    }

    @Test func pausedCountdownShiftsItsStart() {
        var state = apply(lobby(), .loading, seq: 4, at: 1)
        state = apply(state, .countdown(film: 1, startsInMs: 3000, timeLimitMs: 30000, participants: ["me"]), seq: 5, at: 2)
        state = apply(state, .paused(PvPSnapshot.Paused(remainingMs: 32000, autoResumeInMs: 300_000)), seq: 6, at: 3)
        #expect(machine.reduce(state, .tick, now: at(10)).phase == .countdown)
        state = apply(state, .resumed(startsInMs: 3000), seq: 7, at: 10)
        #expect(state.film?.startsAt == at(15))
        #expect(state.film?.endsAt == at(45))
    }

    @Test func revealThenReadyForTheNextFilm() {
        var state = playing()
        let answer = PvPAnswer(mediaKey: "movie_1", tmdbId: 1, mediaType: .movie, title: "One", originalTitle: "One", year: 2001, posterPath: nil)
        let reveal = PvPReveal(film: 1, answer: answer, results: [PvPFilmResult(uid: "me", solvedAtFrame: 2, ms: 4000, points: 837)],
                               standings: [PvPStanding(uid: "me", place: 1, total: 837, hp: nil), PvPStanding(uid: "rival", place: 2, total: 0, hp: nil)],
                               duel: nil, nextInMs: 8000)
        state = apply(state, .reveal(reveal), seq: 9, at: 20)
        state = apply(state, .prepare(PvPPrepare(film: 2, total: 5, frames: Self.frames, spares: [], ready: nil)), seq: 9, at: 20)
        #expect(state.phase == .reveal)
        #expect(state.film == nil)
        #expect(state.reveal?.nextAt == at(28))
        #expect(state.preparation?.film == 2)
        #expect(state.standings.first?.total == 837)
        #expect(machine.reduce(state, .tick, now: at(28)).phase == .ready)
    }

    @Test func joiningPlayerIsRankedAndHostMoves() {
        var state = apply(lobby(), .player(Self.player("late", joined: 5)), seq: 4, at: 1)
        #expect(state.players.map(\.uid) == ["me", "rival", "late"])
        #expect(state.standings.map(\.uid) == ["me", "rival", "late"])
        state = apply(state, .player(Self.player("rival", host: true, joined: 1)), seq: 5, at: 2)
        #expect(!state.isHost)
        #expect(state.player("rival")?.isHost == true)
        state = apply(state, .playerRemoved(uid: "late", reason: "kicked"), seq: 6, at: 3)
        #expect(state.players.count == 2)
        #expect(state.standings.count == 2)
    }

    @Test func errorsBecomeNotices() {
        let state = apply(lobby(), .error(code: "not_enough_players", message: "At least two players are needed"), seq: 3, at: 1)
        #expect(state.notice == PvPMatchNotice(code: "not_enough_players", message: "At least two players are needed", at: at(1)))
    }

    @Test(arguments: [
        (PvPTransportClosure.socket(code: 4000, reason: "left"), PvPMatchClosure.left),
        (.socket(code: 4001, reason: "replaced"), .replaced),
        (.socket(code: 4003, reason: "kicked"), .kicked),
        (.socket(code: 4004, reason: "room_closed"), .roomClosed),
        (.socket(code: 4030, reason: "removed_for_flooding"), .removedForFlooding),
        (.refused(status: 404, code: "room_not_found"), .refused(code: "room_not_found")),
        (.refused(status: 403, code: "kicked"), .kicked),
        (.cancelled, .disconnected)
    ])
    func closuresMapToPhases(closure: PvPTransportClosure, expected: PvPMatchClosure) {
        let state = machine.reduce(lobby(), .transport(.closed(closure)), now: at(1))
        #expect(state.phase == .closed(expected))
    }

    @Test func linkModeIsKept() {
        let state = machine.reduce(lobby(), .transport(.link(.polling)), now: at(1))
        #expect(state.link == .polling)
    }

    @Test func duelOutcomes() {
        let settings = PvPSettings(kind: .duel, mediaType: .movie, films: 20, frames: 6, timeLimitSec: 30, hp: 3000, maxFilms: 20)
        let snapshot = PvPSnapshot(seq: 1, phase: .lobby, code: "DUELXX", you: "me", hostUid: nil, settings: settings,
                                   players: [Self.player("me"), Self.player("rival", joined: 1)], film: nil, prepare: nil,
                                   paused: nil, standings: [], lastReveal: nil, finished: nil, duel: nil)
        let lobby = apply(PvPMatchState(code: "DUELXX"), .snapshot(snapshot), seq: 1, at: 0)
        #expect(lobby.duel?.hp == ["me": 3000, "rival": 3000])

        let cases: [(PvPFinishReason, String?, PvPMatchOutcome)] = [
            (.knockout, "me", .victory), (.filmsDone, "rival", .defeat), (.draw, nil, .draw),
            (.forfeit, "me", .forfeitVictory), (.forfeit, "rival", .forfeitDefeat), (.abandoned, nil, .abandoned)
        ]
        for (reason, winner, outcome) in cases {
            let state = apply(lobby, .finished(PvPFinished(reason: reason, winnerUid: winner, standings: [], films: [])), seq: 9, at: 5)
            #expect(state.result?.outcome == outcome)
            #expect(state.result?.id == "DUELXX:")
        }
    }
}
