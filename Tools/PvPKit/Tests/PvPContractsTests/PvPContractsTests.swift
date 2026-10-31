import Foundation
import Testing
@testable import PvPContracts

struct PvPContractsTests {
    @Test func decodesEnvelopeWithSeq() throws {
        let json = #"{"t":"deadline","film":2,"endsInMs":15000,"seq":41}"#
        let envelope = try JSONDecoder().decode(PvPEnvelope.self, from: Data(json.utf8))
        #expect(envelope == PvPEnvelope(seq: 41, message: .deadline(film: 2, endsInMs: 15000)))
    }

    @Test func encodesClientMessage() throws {
        let data = try JSONEncoder().encode(PvPClientMessage.guess(film: 1, frame: 2, tmdbId: 7, mediaType: .movie))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["t"] as? String == "guess")
        #expect(object?["tmdbId"] as? Int == 7)
    }

    @Test func resultRoundTrips() throws {
        let result = PvPMatchResult(
            id: "ABCDEF:movie_1",
            code: "ABCDEF",
            you: "u1",
            settings: PvPSettings(kind: .duel, mediaType: .movie, films: 20, frames: 6, timeLimitSec: 30, hp: 3000, maxFilms: 20),
            players: [PvPResultPlayer(uid: "u1", name: "NoirGaffer", icon: "reel", color: "red")],
            finished: PvPFinished(reason: .knockout, winnerUid: "u1", standings: [], films: []),
            outcome: .place(2),
            savedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try JSONDecoder().decode(PvPMatchResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }

    @Test func settingsDecodeWithAndWithoutSeats() throws {
        let fresh = #"{"t":"settings","settings":{"kind":"room","mediaType":"movie","films":10,"frames":6,"timeLimitSec":45,"maxPlayers":8}}"#
        let old = #"{"t":"settings","settings":{"kind":"room","mediaType":"movie","films":10,"frames":6,"timeLimitSec":45}}"#
        guard case let .settings(withSeats) = try JSONDecoder().decode(PvPEnvelope.self, from: Data(fresh.utf8)).message,
              case let .settings(withoutSeats) = try JSONDecoder().decode(PvPEnvelope.self, from: Data(old.utf8)).message else {
            Issue.record("not settings")
            return
        }
        #expect(withSeats.maxPlayers == 8)
        #expect(withoutSeats.maxPlayers == nil)
    }

    @Test func closureExposesCloseCode() {
        #expect(PvPTransportClosure.socket(code: 4003, reason: "kicked").closeCode == .kicked)
        #expect(PvPTransportClosure.cancelled.closeCode == nil)
    }
}
