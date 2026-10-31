import Foundation
import Testing
@testable import PvPMatch

struct RecordedLine {
    let at: TimeInterval
    let envelope: PvPEnvelope?
    let reconnect: Bool
    let expect: PvPSnapshot?
}

enum Recording {
    static func load(_ name: String) throws -> [RecordedLine] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Resources"))
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { text in
            let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let envelope = try object["msg"].map { try decoder.decode(PvPEnvelope.self, from: JSONSerialization.data(withJSONObject: $0)) }
            let expect = try object["expect"].map { try decoder.decode(PvPSnapshot.self, from: JSONSerialization.data(withJSONObject: $0)) }
            return RecordedLine(at: (object["at"] as? Double ?? 0) / 1000, envelope: envelope, reconnect: object["reconnect"] != nil, expect: expect)
        }
    }
}

struct StateView: Equatable {
    let phase: String
    let you: String?
    let players: [String]
    let film: String?
    let progress: [String]
    let frames: [String]?
    let preparation: String?
    let standings: [String]
    let hp: [String: Int]?
    let paused: Bool
    let finished: PvPFinished?

    init(_ state: PvPMatchState) {
        let ms = { (date: Date?) in date.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) } }
        phase = "\(state.phase)"
        you = state.you
        players = state.players.map {
            "\($0.uid) \($0.name) host=\($0.isHost) you=\($0.isYou) ready=\($0.ready) \($0.connection) left=\($0.left) forfeit=\(ms($0.forfeitAt).map(String.init) ?? "-")"
        }
        film = state.film.map { film in
            let starts = state.phase == .countdown ? ms(film.startsAt).map(String.init) ?? "" : "-"
            return "\(film.number)/\(film.total) ends=\(ms(film.endsAt)!) starts=\(starts) mine=\(film.yourFrame.map(String.init) ?? "-"):\(film.yourStatus.map(\.rawValue) ?? "-") with=\(film.participants.sorted())"
        }
        progress = (state.film?.progress ?? []).map { "\($0.uid) \($0.frame) \($0.status)" }.sorted()
        frames = state.film?.frames?.map(\.path)
        preparation = state.preparation.map { "\($0.film)/\($0.total) \($0.frames.map(\.path)) \($0.spares.map(\.path))" }
        standings = state.standings.map { "\($0.uid) \($0.place) \($0.total ?? -1) \($0.hp ?? -1)" }
        hp = state.duel?.hp
        paused = state.pause != nil
        finished = state.result?.finished
    }
}

extension StateView {
    func difference(from other: StateView) -> String {
        let mine = Mirror(reflecting: self).children
        let theirs = Array(Mirror(reflecting: other).children)
        return zip(mine, theirs).compactMap { a, b in
            "\(a.value)" == "\(b.value)" ? nil : "\(a.label ?? ""): \(a.value) ≠ \(b.value)"
        }.joined(separator: "; ")
    }
}

struct Replay {
    let machine = PvPMatchMachine()
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    var state = PvPMatchState(code: "")
    var checked = 0

    mutating func run(_ lines: [RecordedLine]) {
        for line in lines {
            let now = base.addingTimeInterval(line.at)
            state = machine.reduce(state, .tick, now: now)
            if line.reconnect {
                state = machine.reduce(state, .transport(.link(.reconnecting)), now: now)
                continue
            }
            guard let envelope = line.envelope else { continue }
            if case let .unknown(type) = envelope.message { Issue.record("unknown message \(type)") }
            state = machine.reduce(state, .transport(.message(envelope)), now: now)
            if case .welcome = envelope.message { state = machine.reduce(state, .transport(.link(.socket)), now: now) }
            invariants(now: now)

            if let snapshot = line.expect {
                let expected = machine.reduce(PvPMatchState(code: snapshot.code), .transport(.message(PvPEnvelope(seq: snapshot.seq, message: .snapshot(snapshot)))), now: now)
                let mine = StateView(state)
                let theirs = StateView(expected)
                #expect(mine == theirs, "at \(line.at)s after \(envelope.message): \(mine.difference(from: theirs))")
                checked += 1
            }
        }
    }

    func invariants(now: Date) {
        switch state.phase {
        case .countdown, .playing:
            let film = state.film
            #expect(film != nil)
            if let film, let frames = film.frames {
                #expect(frames.count == state.settings?.frames)
                #expect((1...frames.count).contains(film.yourFrame ?? 0))
                #expect(film.participants.contains(state.you ?? ""))
            }
            if state.phase == .playing { #expect(now >= state.film?.startsAt ?? .distantFuture) }
        case .finished:
            #expect(state.result != nil)
        default:
            break
        }
        #expect(state.players.filter(\.isYou).count <= 1)
        #expect(state.players.filter(\.isHost).count <= 1)
    }
}

struct RecordedTrafficTests {
    @Test(arguments: ["room-8x10-drop", "room-host", "duel-drop", "duel-forfeit"])
    func replayMatchesServerSnapshots(name: String) throws {
        let lines = try Recording.load(name)
        var replay = Replay()
        replay.run(lines)
        #expect(replay.checked > 10)
        #expect(replay.state.phase == .finished)

        let last = lines.compactMap { line -> PvPFinished? in
            if case let .finished(finished)? = line.envelope?.message { finished } else { nil }
        }.last
        #expect(replay.state.result?.finished == last)
    }

    @Test func countsRecordedMessages() throws {
        let total = try ["room-8x10-drop", "room-host", "duel-drop", "duel-forfeit"].map { try Recording.load($0).filter { $0.envelope != nil }.count }.reduce(0, +)
        #expect(total >= 400)
    }

    @Test func roomReplayEndsWithPlace() throws {
        var replay = Replay()
        replay.run(try Recording.load("room-host"))
        guard case let .place(place)? = replay.state.result?.outcome else {
            Issue.record("no place in \(String(describing: replay.state.result?.outcome))")
            return
        }
        #expect(place == replay.state.standings.first { $0.uid == replay.state.you }?.place)
        #expect(replay.state.result?.players.count == 4)
    }

    @Test func duelForfeitIsAVictoryForTheOneWhoStayed() throws {
        var replay = Replay()
        replay.run(try Recording.load("duel-forfeit"))
        #expect(replay.state.result?.outcome == .forfeitVictory)
        #expect(replay.state.result?.finished.reason == .forfeit)
    }

    @Test func droppedDuelPlayerSeesTheForfeitCountdownOfNobodyAfterReturning() throws {
        var replay = Replay()
        replay.run(try Recording.load("duel-drop"))
        #expect(replay.state.players.allSatisfy { $0.forfeitAt == nil })
        #expect([.victory, .defeat, .draw].contains(replay.state.result?.outcome))
    }
}
