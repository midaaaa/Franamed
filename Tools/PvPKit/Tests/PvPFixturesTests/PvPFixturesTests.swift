import Foundation
import Testing
@testable import PvPFixtures

struct PvPFixturesTests {
    @Test func everyPhaseHasAFixture() {
        let states = PvPMatchFixtures.all.map(\.state)
        let phases = Set(states.map { "\($0.phase)" })
        for phase in ["lobby", "loading", "ready", "countdown", "playing", "reveal", "finished", "closed(PvPFixtures.PvPMatchClosure.kicked)"] {
            #expect(phases.contains { $0.hasPrefix(phase) }, "no fixture for \(phase)")
        }
        let outcomes = states.compactMap { $0.result?.outcome }
        for outcome in [PvPMatchOutcome.victory, .defeat, .forfeitVictory, .forfeitDefeat, .draw, .abandoned, .place(1), .place(2)] {
            #expect(outcomes.contains(outcome))
        }
        #expect(states.contains { $0.link == .polling })
        #expect(states.contains { $0.pause != nil })
        #expect(states.contains { $0.players.contains { $0.forfeitAt != nil && $0.connection == .offline } })
        #expect(states.contains { $0.kind == .room && $0.isHost && $0.phase == .lobby })
        #expect(states.contains { $0.kind == .room && !$0.isHost && $0.phase == .lobby })
        #expect(states.contains { $0.reveal?.duel != nil })
        #expect(states.contains { $0.film?.deadlineCut == true })
    }

    @Test func fixturesAreSelfConsistent() {
        for (name, state) in PvPMatchFixtures.all {
            #expect(state.me != nil, "\(name): no you")
            #expect(state.players.filter(\.isHost).count <= 1, "\(name): hosts")
            if state.phase == .playing || state.phase == .countdown {
                #expect(state.film != nil, "\(name): no film")
            }
            if let film = state.film, film.isParticipating {
                #expect(film.frames?.count == state.settings?.frames, "\(name): frames")
                #expect(film.participants.contains(PvPMatchFixtures.you), "\(name): participants")
            }
            if state.phase == .finished {
                #expect(state.result != nil, "\(name): no result")
            }
        }
    }

    @Test func previewSessionPlaysItsSteps() async {
        let session = PvPPreviewSession(steps: [
            .init(after: .zero) { PvPMatchFixtures.lobbyHost },
            .init(after: .milliseconds(30)) { PvPMatchFixtures.countdown },
            .init(after: .milliseconds(30)) { PvPMatchFixtures.finishedRoom }
        ], loops: false)
        var phases: [PvPMatchPhase] = []
        for await state in session.states() {
            phases.append(state.phase)
            if state.phase == .finished { break }
        }
        #expect(phases.first == .lobby)
        #expect(phases.last == .finished)
        await session.guess(tmdbId: 603, mediaType: .movie)
        #expect(session.actions == ["guess 603"])
    }

    @Test func previewSessionGivesEverySubscriberTheCurrentState() async {
        let session = PvPPreviewSession(PvPMatchFixtures.paused)
        var first = session.states().makeAsyncIterator()
        var second = session.states().makeAsyncIterator()
        #expect(await first.next()?.pause != nil)
        #expect(await second.next()?.pause != nil)
    }

    @Test(arguments: [PvPRecordedTraffic.room, PvPRecordedTraffic.duel])
    func recordedTrafficDecodes(traffic: String) {
        let lines = PvPRecordedTraffic.lines(traffic)
        #expect(lines.count == traffic.split(separator: "\n").count)
        #expect(!lines.contains { if case .unknown? = $0.msg?.message { true } else { false } })
    }

    @Test func replayTransportPlaysTheRecording() async {
        let transport = PvPReplayTransport(traffic: PvPRecordedTraffic.duel, speed: 2000)
        await transport.connect(to: URL(string: "ws://fixture")!, credential: .ticket("t"), lastSeq: nil)
        var messages = 0
        var links: [PvPLinkMode] = []
        var finished = false
        for await event in transport.events {
            switch event {
            case .message(let envelope):
                messages += 1
                if case .finished = envelope.message { finished = true }
            case .link(let mode):
                links.append(mode)
            case .closed:
                break
            }
            if finished { break }
        }
        #expect(finished)
        #expect(links.contains(.reconnecting))
        #expect(links.first == .connecting)
        #expect(messages > 100)
    }
}
