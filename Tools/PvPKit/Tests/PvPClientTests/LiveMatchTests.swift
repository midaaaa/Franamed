import Foundation
import Testing
@testable import PvPClient

extension PvPTransportTiming {
    static let test = PvPTransportTiming(
        ping: .milliseconds(300),
        silence: .seconds(2),
        connectTimeout: .seconds(2),
        reconnectDelay: .milliseconds(100),
        failuresBeforePolling: 2,
        attemptsWithoutResume: 3,
        poll: .milliseconds(500),
        pollTimeout: .seconds(2),
        socketRetry: .seconds(3),
        burst: 20,
        refill: .milliseconds(500)
    )
}

func liveTransport() -> any PvPTransport {
    #if os(Linux)
    PvPSocketTransport(sockets: POSIXWebSockets(), timing: .test)
    #else
    PvPSocketTransport(timing: .test)
    #endif
}

struct Player {
    let service: BackendPvPService
    let session: PvPMatchSession
    let log: StateLog
    let store: PvPJSONResultStore

    var uid: String? { log.last?.you }

    static func make(server: FakeServer, room: PvPRoomTicket, code: String) -> Player {
        let client = BackendAPIClient(configuration: BackendConfiguration(apiBaseURL: server.baseURL, imageBaseURL: ""))
        let store = PvPJSONResultStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("pvp-\(UUID().uuidString).json"))
        let session = PvPMatchSession(room: room, code: code, reducer: PvPMatchMachine(), preloader: TestPreloader(),
                                      resultStore: store, makeTransport: liveTransport)
        return Player(service: BackendPvPService(client: client), session: session, log: StateLog(session), store: store)
    }

    func skipWhenAsked() -> Task<Void, Never> {
        let session = session
        return Task {
            for await state in session.states() {
                if state.phase == .playing, state.film?.yourStatus == .thinking, state.film?.answering == false, state.film?.resumesAt == nil {
                    await session.skip()
                }
            }
        }
    }
}

@Suite(.serialized)
struct LiveMatchTests {
    let server: FakeServer

    init() throws {
        server = try FakeServer(config: ["pvpCountdownSec": 1, "pvpRevealSec": 1, "pvpReadyTimeoutSec": 5, "pvpDuelHP": 1500])
    }

    func host(_ room: PvPCreateRoom) async throws -> (Player, String) {
        let client = BackendAPIClient(configuration: BackendConfiguration(apiBaseURL: server.baseURL, imageBaseURL: ""))
        let ticket = try await BackendPvPService(client: client).createRoom(room)
        let code = try #require(ticket.code)
        let player = Player.make(server: server, room: ticket, code: code)
        await player.session.connect()
        #expect(try await waitUntil { player.log.last?.phase == .lobby })
        return (player, code)
    }

    @Test func roomWithBotsSurvivesADrop() async throws {
        let (me, code) = try await host(PvPCreateRoom(kind: .room, mediaType: .movie, films: 5))
        try await server.control("bot", ["name": "NoirGaffer", "code": code])
        try await server.control("bot", ["name": "SilentFoley", "code": code])
        #expect(try await waitUntil { me.log.last?.players.count == 3 })
        #expect(me.log.last?.isHost == true)

        let skipping = me.skipWhenAsked()
        defer { skipping.cancel() }
        await me.session.start()
        #expect(try await waitUntil { me.log.last?.film?.number == 2 })
        try await server.control("drop", ["uid": try #require(me.uid)])
        #expect(try await waitUntil(timeout: .seconds(90)) { me.log.last?.phase == .finished })

        let state = try #require(me.log.last)
        #expect(state.result?.finished.films.count == 5)
        #expect(state.result?.players.count == 3)
        #expect(me.log.states.contains { $0.link == .reconnecting })
        #expect(try await waitUntil { await me.store.results().count == 1 })
        #expect(try await server.control("stats", ["uid": try #require(me.uid)])["sockets"] as? Int == 2)
    }

    @Test func duelAgainstABotOverPolling() async throws {
        let (me, code) = try await host(PvPCreateRoom(kind: .duel, mediaType: .movie))
        try await server.control("bot", ["name": "MidnightReel", "code": code, "ready": true, "accuracy": 1])
        let skipping = me.skipWhenAsked()
        defer { skipping.cancel() }
        await me.session.ready()
        #expect(try await waitUntil { me.log.last?.phase == .playing })

        try await server.control("refuse-sockets", ["count": 100])
        try await server.control("drop", ["uid": try #require(me.uid)])
        #expect(try await waitUntil { me.log.last?.link == .polling })
        #expect(try await waitUntil(timeout: .seconds(90)) { me.log.last?.phase == .finished })
        let result = try #require(me.log.last?.result)
        #expect(result.outcome == .defeat)
        #expect(result.finished.reason == .knockout)
        #expect(try await waitUntil { await me.store.results().first?.id == result.id })
        try await server.control("refuse-sockets", ["count": 0])
    }

    @Test func guessLostInASilentSocketIsSentAgain() async throws {
        let (me, code) = try await host(PvPCreateRoom(kind: .duel, mediaType: .movie))
        try await server.control("bot", ["name": "RetroSlate", "code": code, "ready": true, "accuracy": 0, "think": [20000, 25000]])
        await me.session.ready()
        #expect(try await waitUntil { me.log.last?.phase == .playing && me.log.last?.film?.yourStatus == .thinking })
        let uid = try #require(me.uid)

        try await server.control("drop", ["uid": uid, "silent": true])
        await me.session.guess(tmdbId: 1, mediaType: .movie)
        #expect(try await waitUntil(timeout: .seconds(10)) { me.log.last?.film?.yourFrame == 2 })
        let guesses = try await server.received(by: uid).filter { $0.text.contains(#""t":"guess""#) }
        #expect(guesses.count == 1)
        #expect(try await server.control("stats", ["uid": uid])["sockets"] as? Int == 2)
    }

    @Test func tooManyMessagesOnlyReconnects() async throws {
        let (me, _) = try await host(PvPCreateRoom(kind: .room, mediaType: .movie))
        try await server.control("close", ["uid": try #require(me.uid), "code": 4029, "reason": "too_many_messages"])
        #expect(try await waitUntil { me.log.states.contains { $0.link == .reconnecting } && me.log.last?.link == .socket })
        #expect(me.log.last?.phase == .lobby)
    }

    @Test(arguments: [(4004, PvPMatchClosure.roomClosed), (4030, .removedForFlooding)])
    func finalCodesEndTheSession(code: Int, closure: PvPMatchClosure) async throws {
        let (me, _) = try await host(PvPCreateRoom(kind: .room, mediaType: .movie))
        try await server.control("close", ["uid": try #require(me.uid), "code": code, "reason": "bye"])
        #expect(try await waitUntil { me.log.last?.phase == .closed(closure) })
        await me.session.connect()
        try await Task.sleep(for: .milliseconds(300))
        #expect(me.log.last?.phase == .closed(closure))
    }

    @Test func kickedByTheHost() async throws {
        let bot = try await server.control("bot", ["name": "CultEditor", "create": ["kind": "room", "mediaType": "movie"]])
        let code = try #require(bot["code"] as? String)
        let client = BackendAPIClient(configuration: BackendConfiguration(apiBaseURL: server.baseURL, imageBaseURL: ""))
        let ticket = try await BackendPvPService(client: client).ticket(code: code)
        let me = Player.make(server: server, room: ticket, code: code)
        await me.session.connect()
        #expect(try await waitUntil { me.log.last?.phase == .lobby })
        #expect(me.log.last?.isHost == false)

        try await server.control("bot-send", ["name": "CultEditor", "msg": ["t": "kick", "uid": try #require(me.uid)]])
        #expect(try await waitUntil { me.log.last?.phase == .closed(.kicked) })
        await #expect(throws: BackendError.self) { try await BackendPvPService(client: client).ticket(code: code) }
    }

    @Test func disconnectAndComeBack() async throws {
        let (me, code) = try await host(PvPCreateRoom(kind: .room, mediaType: .movie))
        try await server.control("bot", ["name": "NeonUsher", "code": code])
        await me.session.disconnect()
        #expect(try await waitUntil { me.log.last?.phase == .closed(.disconnected) })
        await me.session.connect()
        #expect(try await waitUntil { me.log.last?.phase == .lobby && me.log.last?.players.count == 2 })
        #expect(me.log.last?.isHost == true)
    }
}
