import Foundation
import Synchronization
import Testing
@testable import PvPTransportKit

final class EventLog: Sendable {
    private let items = Mutex<[PvPTransportEvent]>([])

    init(_ transport: PvPSocketTransport) {
        Task {
            for await event in transport.events { self.append(event) }
        }
    }

    private func append(_ event: PvPTransportEvent) {
        items.withLock { $0.append(event) }
    }

    var events: [PvPTransportEvent] { items.withLock { $0 } }

    var links: [PvPLinkMode] {
        events.compactMap { if case let .link(mode) = $0 { mode } else { nil } }
    }

    var messages: [PvPServerMessage] {
        events.compactMap { if case let .message(envelope) = $0 { envelope.message } else { nil } }
    }

    var welcomes: Int {
        messages.filter { if case .welcome = $0 { true } else { false } }.count
    }

    var closure: PvPTransportClosure? {
        events.lazy.compactMap { if case let .closed(closure) = $0 { closure } else { nil } }.first
    }
}

extension PvPTransportTiming {
    static let fast = PvPTransportTiming(
        ping: .milliseconds(300),
        silence: .seconds(3),
        connectTimeout: .seconds(2),
        reconnectDelay: .milliseconds(100),
        failuresBeforePolling: 2,
        attemptsWithoutResume: 3,
        poll: .milliseconds(500),
        pollTimeout: .seconds(2),
        socketRetry: .seconds(2),
        burst: 20,
        refill: .milliseconds(250)
    )
}

func makeTransport(timing: PvPTransportTiming = .fast) -> PvPSocketTransport {
    #if os(Linux)
    PvPSocketTransport(sockets: POSIXWebSockets(), timing: timing)
    #else
    PvPSocketTransport(timing: timing)
    #endif
}

@Suite(.serialized)
struct PvPSocketTransportTests {
    let server: FakeServer

    init() throws {
        server = try FakeServer()
    }

    func connected(timing: PvPTransportTiming = .fast) async throws -> (PvPSocketTransport, EventLog, uid: String, code: String) {
        let room = try await server.createRoom(["kind": "room", "mediaType": "movie", "films": 5])
        let transport = makeTransport(timing: timing)
        let log = EventLog(transport)
        await transport.connect(to: room.socketURL, credential: .ticket(room.ticket), lastSeq: nil)
        #expect(try await waitUntil { log.welcomes == 1 && log.links.last == .socket })
        return (transport, log, room.uid, room.code)
    }

    @Test func connectsWithTicketAndPings() async throws {
        let (transport, log, uid, _) = try await connected()
        guard case let .welcome(welcome)? = log.messages.first else {
            Issue.record("first message is not welcome")
            return
        }
        #expect(welcome.you.uid == uid)
        #expect(welcome.snapshot?.phase == .lobby)

        try await Task.sleep(for: .seconds(1))
        let pings = try await server.received(by: uid).filter { $0.text == #"{"t":"ping"}"# }
        #expect(pings.count >= 2)
        #expect(!log.messages.contains { if case .pong = $0 { true } else { false } })
        await transport.close()
        #expect(try await waitUntil { log.closure == .cancelled })
    }

    @Test func reconnectsWithResumeTokenAfterDrop() async throws {
        let (transport, log, uid, _) = try await connected()
        try await server.control("drop", ["uid": uid])
        #expect(try await waitUntil { log.welcomes == 2 })
        #expect(log.links.contains(.reconnecting))
        #expect(log.links.last == .socket)
        let stats = try await server.control("stats", ["uid": uid])
        #expect(stats["sockets"] as? Int == 2)
        await transport.close()
    }

    @Test func noticesSilentSocket() async throws {
        let (transport, log, uid, _) = try await connected()
        try await server.control("drop", ["uid": uid, "silent": true])
        try await Task.sleep(for: .seconds(2))
        #expect(log.welcomes == 1)
        #expect(try await waitUntil(timeout: .seconds(5)) { log.welcomes == 2 })
        await transport.close()
    }

    @Test func fallsBackToPollingAndReturnsToSocket() async throws {
        let (transport, log, uid, code) = try await connected()
        try await server.control("refuse-sockets", ["count": 2])
        try await server.control("drop", ["uid": uid])
        #expect(try await waitUntil { log.links.last == .polling })

        let bot = try await server.control("bot", ["name": "NoirGaffer", "code": code])
        let botUid = try #require(bot["uid"] as? String)
        #expect(try await waitUntil {
            log.messages.contains { if case let .snapshot(snapshot) = $0 { snapshot.players.contains { $0.uid == botUid } } else { false } }
        })

        let before = Date().timeIntervalSince1970 * 1000
        await transport.send(.settings(films: 10, frames: nil, timeLimitSec: nil))
        #expect(try await waitUntil(timeout: .seconds(2)) {
            try await server.received(by: uid).contains { $0.via == "poll" && $0.text.contains("settings") }
        })
        let sent = try await server.received(by: uid).first { $0.via == "poll" && $0.text.contains("settings") }
        #expect(try #require(sent).at - before < 400)

        #expect(try await waitUntil(timeout: .seconds(6)) { log.links.last == .socket })
        #expect(log.welcomes == 2)
        let stats = try await server.control("stats", ["uid": uid])
        #expect(stats["socketsRefused"] as? Int == 2)
        #expect((stats["polls"] as? Int ?? 0) >= 2)
        await transport.close()
    }

    @Test func reconnectsAfterTooManyMessages() async throws {
        let (transport, log, uid, _) = try await connected()
        try await server.control("close", ["uid": uid, "code": 4029, "reason": "too_many_messages"])
        #expect(try await waitUntil { log.welcomes == 2 })
        #expect(log.closure == nil)
        await transport.close()
    }

    @Test(arguments: [4003, 4004, 4030, 4000, 4001])
    func stopsOnFinalCloseCode(code: Int) async throws {
        let (_, log, uid, _) = try await connected()
        try await server.control("close", ["uid": uid, "code": code, "reason": "bye"])
        #expect(try await waitUntil { log.closure != nil })
        #expect(log.closure?.closeCode?.rawValue == code)
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.welcomes == 1)
    }

    @Test func stopsWhenKickedByHost() async throws {
        let bot = try await server.control("bot", ["name": "SilentFoley", "create": ["kind": "room", "mediaType": "movie"]])
        let code = try #require(bot["code"] as? String)
        let player = try await server.join(code)
        let transport = makeTransport()
        let log = EventLog(transport)
        await transport.connect(to: player.socketURL, credential: .ticket(player.ticket), lastSeq: nil)
        #expect(try await waitUntil { log.welcomes == 1 })

        try await server.control("bot-send", ["name": "SilentFoley", "msg": ["t": "kick", "uid": player.uid]])
        #expect(try await waitUntil { log.closure != nil })
        #expect(log.closure?.closeCode == .kicked)
    }

    @Test func refusesForgedTicket() async throws {
        let room = try await server.createRoom(["kind": "duel", "mediaType": "movie"])
        let transport = makeTransport()
        let log = EventLog(transport)
        await transport.connect(to: room.socketURL, credential: .ticket("pvp1.forged.mac"), lastSeq: nil)
        #expect(try await waitUntil { log.closure != nil })
        #expect(log.closure == .refused(status: 401, code: "token_invalid"))
    }

    @Test func pacesOutgoingMessages() async throws {
        let (transport, log, uid, _) = try await connected()
        let start = Date().timeIntervalSince1970 * 1000
        for _ in 0..<26 { await transport.send(.unready) }
        #expect(try await waitUntil(timeout: .seconds(5)) {
            try await server.received(by: uid).filter { $0.text.contains("unready") }.count == 26
        })
        let times = try await server.received(by: uid).filter { $0.text.contains("unready") }.map { $0.at - start }
        #expect(times[19] < 300)
        #expect(times[25] - times[19] >= 5 * 250 - 100)
        #expect(log.closure == nil)
        await transport.close()
    }

    @Test func resendsUnsentThroughQueueAfterReconnect() async throws {
        let (transport, log, uid, _) = try await connected()
        for _ in 0..<20 { await transport.send(.unready) }
        #expect(try await waitUntil { try await server.received(by: uid).count(where: { $0.text.contains("unready") }) == 20 })

        for _ in 0..<6 { await transport.send(.unready) }
        try await server.control("drop", ["uid": uid])
        #expect(try await waitUntil { log.welcomes == 2 })
        #expect(try await waitUntil(timeout: .seconds(5)) {
            try await server.received(by: uid).count(where: { $0.text.contains("unready") }) >= 26
        })
        let times = try await server.received(by: uid).filter { $0.text.contains("unready") }.map(\.at)
        let gaps = zip(times.dropFirst(20), times.dropFirst(21)).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 >= 150 })
        await transport.close()
    }
}
