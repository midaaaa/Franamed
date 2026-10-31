import Foundation
import Synchronization
@testable import PvPClient

actor ScriptedTransport: PvPTransport {
    nonisolated let events: AsyncStream<PvPTransportEvent>
    private let continuation: AsyncStream<PvPTransportEvent>.Continuation
    private(set) var sent: [PvPClientMessage] = []
    private(set) var connects: [(credential: PvPCredential, lastSeq: Int?)] = []
    private(set) var closed = false

    init() {
        (events, continuation) = AsyncStream.makeStream(of: PvPTransportEvent.self)
    }

    func connect(to socketURL: URL, credential: PvPCredential, lastSeq: Int?) {
        connects.append((credential, lastSeq))
    }

    func send(_ message: PvPClientMessage) {
        sent.append(message)
    }

    func close() {
        closed = true
        continuation.yield(.closed(.cancelled))
        continuation.finish()
    }

    func emit(_ event: PvPTransportEvent) {
        continuation.yield(event)
    }

    func emit(_ message: PvPServerMessage, seq: Int? = nil) {
        continuation.yield(.message(PvPEnvelope(seq: seq, message: message)))
    }
}

final class TransportFactory: Sendable {
    private let made = Mutex<[ScriptedTransport]>([])

    var transports: [ScriptedTransport] { made.withLock { $0 } }

    func make() -> any PvPTransport {
        let transport = ScriptedTransport()
        made.withLock { $0.append(transport) }
        return transport
    }
}

final class TestPreloader: PvPFramePreloader {
    private let broken = Mutex<[Int]>([])
    private let calls = Mutex(0)

    init(brokenFirst: [Int] = []) {
        broken.withLock { $0 = brokenFirst }
    }

    var count: Int { calls.withLock { $0 } }

    func preload(frames: [PvPFrame], spares: [PvPFrame]) async -> PvPFramePreload {
        calls.withLock { $0 += 1 }
        if let index = broken.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return .broken(index: index) }
        return .ready
    }
}

actor MemoryResultStore: PvPResultStore {
    private(set) var saves: [PvPMatchResult] = []

    func save(_ result: PvPMatchResult) { saves.append(result) }
    func results() -> [PvPMatchResult] { saves }
    func remove(id: String) { saves.removeAll { $0.id == id } }
}

final class StateLog: Sendable {
    private let items = Mutex<[PvPMatchState]>([])

    init(_ session: PvPMatchSession) {
        let stream = session.states()
        Task {
            for await state in stream { self.append(state) }
        }
    }

    private func append(_ state: PvPMatchState) {
        items.withLock { $0.append(state) }
    }

    var states: [PvPMatchState] { items.withLock { $0 } }
    var last: PvPMatchState? { states.last }
}

enum Sample {
    static let roomSettings = PvPSettings(kind: .room, mediaType: .movie, films: 5, frames: 6, timeLimitSec: 30, hp: nil, maxFilms: nil)
    static let frames = (1...6).map { PvPFrame(path: "/f\($0).jpg", width: 1920, height: 1080) }

    static func player(_ uid: String, host: Bool = false) -> PvPPlayer {
        PvPPlayer(uid: uid, name: uid.uppercased(), alias: "A\(uid)", icon: "reel", color: "red", isHost: host, ready: false,
                  connection: .online, left: false, joinedAt: uid == "me" ? 0 : 1, forfeitInMs: nil)
    }

    static func snapshot(seq: Int, phase: PvPPhase = .lobby, film: PvPSnapshot.Film? = nil, finished: PvPFinished? = nil) -> PvPSnapshot {
        PvPSnapshot(seq: seq, phase: phase, code: "ABCDEF", you: "me", hostUid: "me", settings: roomSettings,
                    players: [player("me", host: true), player("rival")], film: film, prepare: nil, paused: nil,
                    standings: [], lastReveal: nil, finished: finished, duel: nil)
    }

    static func playingFilm(frame: Int) -> PvPSnapshot.Film {
        PvPSnapshot.Film(index: 1, total: 5, progress: [PvPProgress(uid: "me", frame: frame, status: .thinking)],
                         startsInMs: 0, endsInMs: 20000, frames: frames, spares: [], yourFrame: frame, yourStatus: .thinking)
    }

    static func welcome(_ snapshot: PvPSnapshot, token: String = "pvpr1.token.mac") -> PvPServerMessage {
        .welcome(PvPWelcome(seq: snapshot.seq, you: .init(uid: "me", resumeToken: token), snapshot: snapshot))
    }

    static let ticket = PvPRoomTicket(code: "ABCDEF", ticket: "pvp1.ticket.mac", socketURL: URL(string: "ws://127.0.0.1:1/v1/pvp/rooms/ABCDEF/ws")!)
}
