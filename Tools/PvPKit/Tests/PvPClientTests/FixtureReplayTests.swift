import Foundation
import Testing
@testable import PvPClient

struct FixtureReplayTests {
    @Test(arguments: [("room", PvPRecordedTraffic.room), ("duel", PvPRecordedTraffic.duel)])
    func sessionPlaysRecordedTrafficToTheEnd(name: String, traffic: String) async throws {
        let store = MemoryResultStore()
        let speed = 400.0
        let transport = PvPReplayTransport(traffic: traffic, speed: speed)
        let start = Date()
        let session = PvPMatchSession(room: Sample.ticket, code: "", reducer: PvPMatchMachine(), preloader: TestPreloader(),
                                      resultStore: store, now: { start.addingTimeInterval(Date().timeIntervalSince(start) * speed) },
                                      makeTransport: { transport })
        let log = StateLog(session)
        await session.connect()
        #expect(try await waitUntil(timeout: .seconds(10)) { log.last?.phase == .finished })
        #expect(try await waitUntil { await store.saves.count == 1 })
        #expect(log.states.contains { $0.phase == .countdown })
        #expect(log.states.contains { $0.phase == .playing })
        #expect(log.states.contains { $0.phase == .reveal })
        let sent = await transport.sent
        #expect(sent.contains { if case .ready = $0 { true } else { false } })
    }
}
