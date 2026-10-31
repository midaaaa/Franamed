import Foundation
import Testing
@testable import PvPClient

struct PvPMatchSessionTests {
    let factory = TransportFactory()
    let preloader: TestPreloader
    let store = MemoryResultStore()
    let session: PvPMatchSession

    init(brokenFirst: [Int] = []) {
        preloader = TestPreloader(brokenFirst: brokenFirst)
        let factory = factory
        session = PvPMatchSession(room: Sample.ticket, code: "ABCDEF", reducer: PvPMatchMachine(), preloader: preloader,
                                  resultStore: store, makeTransport: { factory.make() })
    }

    init() {
        self.init(brokenFirst: [])
    }

    func connected(_ snapshot: PvPSnapshot = Sample.snapshot(seq: 3)) async throws -> (ScriptedTransport, StateLog) {
        let log = StateLog(session)
        await session.connect()
        let transport = try #require(factory.transports.last)
        await transport.emit(Sample.welcome(snapshot), seq: snapshot.seq)
        await transport.emit(.link(.socket))
        #expect(try await waitUntil { log.last?.phase == Self.phase(of: snapshot) && log.last?.link == .socket })
        return (transport, log)
    }

    static func phase(of snapshot: PvPSnapshot) -> PvPMatchPhase {
        switch snapshot.phase {
        case .playing: .playing
        case .finished: .finished
        default: .lobby
        }
    }

    @Test func everySubscriberStartsWithTheCurrentState() async throws {
        _ = try await connected()
        var late = session.states().makeAsyncIterator()
        let first = await late.next()
        #expect(first?.phase == .lobby)
        #expect(first?.you == "me")
        var other = session.states().makeAsyncIterator()
        #expect(await other.next() == first)
    }

    @Test func connectsWithTicketFirst() async throws {
        let (transport, _) = try await connected()
        #expect(await transport.connects.first?.credential == .ticket("pvp1.ticket.mac"))
        await session.ready()
        #expect(await transport.sent == [.ready(film: 0)])
    }

    @Test func loadsFramesAndSaysReady() async throws {
        let (transport, log) = try await connected()
        await transport.emit(.loading, seq: 4)
        await transport.emit(.prepare(PvPPrepare(film: 1, total: 5, frames: Sample.frames, spares: [], ready: nil)), seq: 5)
        #expect(try await waitUntil { await transport.sent.contains(.ready(film: 1)) })
        #expect(try await waitUntil { log.last?.preparation?.status == .ready })
        #expect(preloader.count == 1)
    }

    @Test func reportsABrokenFrameAndLoadsAgain() async throws {
        let session = PvPMatchSessionTests(brokenFirst: [2])
        let (transport, _) = try await session.connected()
        await transport.emit(.prepare(PvPPrepare(film: 1, total: 5, frames: Sample.frames, spares: [], ready: nil)), seq: 4)
        #expect(try await waitUntil { await transport.sent.contains(.frameBroken(film: 1, index: 2)) })
        var replaced = Sample.frames
        replaced[2] = PvPFrame(path: "/spare.jpg", width: 1920, height: 1080)
        await transport.emit(.prepare(PvPPrepare(film: 1, total: 5, frames: replaced, spares: [], ready: nil)), seq: 5)
        #expect(try await waitUntil { await transport.sent.contains(.ready(film: 1)) })
        #expect(session.preloader.count == 2)
    }

    @Test func repeatsAnUnansweredGuessAfterReconnecting() async throws {
        let (transport, log) = try await connected(Sample.snapshot(seq: 7, phase: .playing, film: Sample.playingFilm(frame: 1)))
        await session.guess(tmdbId: 42, mediaType: .movie)
        await session.guess(tmdbId: 42, mediaType: .movie)
        let guess = PvPClientMessage.guess(film: 1, frame: 1, tmdbId: 42, mediaType: .movie)
        #expect(await transport.sent == [guess])
        #expect(try await waitUntil { log.last?.film?.answering == true })

        await transport.emit(.link(.reconnecting))
        await transport.emit(Sample.welcome(Sample.snapshot(seq: 9, phase: .playing, film: Sample.playingFilm(frame: 1))), seq: 9)
        #expect(try await waitUntil { await transport.sent == [guess, guess] })
    }

    @Test func doesNotRepeatAGuessTheServerAlreadyTook() async throws {
        let (transport, _) = try await connected(Sample.snapshot(seq: 7, phase: .playing, film: Sample.playingFilm(frame: 1)))
        await session.skip()
        await transport.emit(Sample.welcome(Sample.snapshot(seq: 9, phase: .playing, film: Sample.playingFilm(frame: 2))), seq: 9)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await transport.sent == [.skip(film: 1, frame: 1)])
        await session.skip()
        #expect(await transport.sent == [.skip(film: 1, frame: 1), .skip(film: 1, frame: 2)])
    }

    @Test func savesTheResultOnce() async throws {
        let (transport, log) = try await connected()
        let finished = PvPFinished(reason: .filmsDone, winnerUid: nil, standings: [PvPStanding(uid: "me", place: 1, total: 900, hp: nil)], films: [])
        await transport.emit(.finished(finished), seq: 10)
        await transport.emit(Sample.welcome(Sample.snapshot(seq: 11, phase: .finished, finished: finished)), seq: 11)
        #expect(try await waitUntil { log.last?.result != nil })
        try await Task.sleep(for: .milliseconds(100))
        #expect(await store.saves.count == 1)
        #expect(await store.saves.first?.outcome == .place(1))
    }

    @Test func disconnectKeepsTheSeatAndComesBackWithTheResumeToken() async throws {
        let (first, log) = try await connected()
        await session.disconnect()
        #expect(await first.closed)
        #expect(try await waitUntil { log.last?.phase == .closed(.disconnected) })

        await session.connect()
        let second = try #require(factory.transports.last)
        #expect(factory.transports.count == 2)
        #expect(await second.connects.first?.credential == .resume("pvpr1.token.mac"))
        #expect(await second.connects.first?.lastSeq == 3)
    }

    @Test func comingBackFromBackgroundRevivesADeadLink() async throws {
        let (transport, _) = try await connected()
        await transport.emit(.link(.polling))
        try await Task.sleep(for: .milliseconds(50))
        await session.setAway(false)
        #expect(await transport.connects.count == 2)
        #expect(await transport.connects.last?.credential == .resume("pvpr1.token.mac"))
        #expect(await transport.sent.last == .away(false))

        await session.disconnect()
        await session.setAway(false)
        #expect(factory.transports.count == 2)
        #expect(await factory.transports.last?.sent == [.away(false)])
    }

    @Test func leavingIsFinal() async throws {
        let (transport, log) = try await connected()
        await session.leave()
        #expect(await transport.sent == [.leave])
        await transport.emit(.closed(.socket(code: 4000, reason: "left")))
        #expect(try await waitUntil { log.last?.phase == .closed(.left) })
        await session.connect()
        #expect(factory.transports.count == 1)
    }

    @Test func countdownBecomesPlayingOnItsOwn() async throws {
        let (transport, log) = try await connected()
        await transport.emit(.prepare(PvPPrepare(film: 1, total: 5, frames: Sample.frames, spares: [], ready: nil)), seq: 4)
        await transport.emit(.countdown(film: 1, startsInMs: 300, timeLimitMs: 30000, participants: ["me", "rival"]), seq: 5)
        #expect(try await waitUntil { log.last?.phase == .countdown })
        #expect(try await waitUntil(timeout: .seconds(2)) { log.last?.phase == .playing })
    }
}
