import Foundation
import Testing
@testable import PvPClient

let wranglerURL = ProcessInfo.processInfo.environment["PVP_WRANGLER_URL"]

final class RemoteBots: Sendable {
    private let process: Process

    init(url: String, code: String, count: Int, ready: Bool) throws {
        let script = FakeServer.packageDirectory.appendingPathComponent("Server/remote-bots.mjs")
        let process = Process()
        process.executableURL = try FakeServer.node()
        process.arguments = ["--no-warnings", script.path, "--url", url, "--code", code, "--count", "\(count)"] + (ready ? ["--ready"] : [])
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        self.process = process
    }

    deinit {
        process.terminate()
    }
}

@Suite(.serialized, .enabled(if: wranglerURL != nil, "set PVP_WRANGLER_URL to a running wrangler dev"))
struct WranglerTests {
    let url = wranglerURL ?? ""

    func me(_ room: PvPCreateRoom) async throws -> (Player, String, BackendPvPService) {
        let client = BackendAPIClient(configuration: BackendConfiguration(apiBaseURL: url, imageBaseURL: ""))
        let service = BackendPvPService(client: client)
        _ = try await service.updateProfile(PvPProfileUpdate(name: "SwiftClient"))
        let ticket = try await service.createRoom(room)
        let code = try #require(ticket.code)
        let store = PvPJSONResultStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("pvp-\(UUID().uuidString).json"))
        let session = PvPMatchSession(room: ticket, code: code, reducer: PvPMatchMachine(), preloader: TestPreloader(),
                                      resultStore: store, makeTransport: liveTransport)
        let player = Player(service: service, session: session, log: StateLog(session), store: store)
        await session.connect()
        #expect(try await waitUntil { player.log.last?.phase == .lobby })
        return (player, code, service)
    }

    @Test func roomAgainstBotsWithADrop() async throws {
        let (me, code, _) = try await me(PvPCreateRoom(kind: .room, mediaType: .movie, films: 5, timeLimitSec: 30))
        let bots = try RemoteBots(url: url, code: code, count: 2, ready: false)
        #expect(try await waitUntil(timeout: .seconds(30)) { me.log.last?.players.count == 3 })
        let skipping = me.skipWhenAsked()
        defer { skipping.cancel() }
        await me.session.start()
        #expect(try await waitUntil(timeout: .seconds(120)) { me.log.last?.film?.number == 2 })
        #if os(Linux)
        POSIXWebSockets.dropAll()
        #endif
        #expect(try await waitUntil(timeout: .seconds(300)) { me.log.last?.phase == .finished })
        #expect(me.log.last?.result?.finished.films.count == 5)
        #if os(Linux)
        #expect(me.log.states.contains { $0.link == .reconnecting })
        #endif
        #expect(try await waitUntil { await me.store.results().count == 1 })
        _ = bots
    }

    @Test func duelAgainstABotWithADrop() async throws {
        let (me, code, _) = try await me(PvPCreateRoom(kind: .duel, mediaType: .movie, timeLimitSec: 30))
        let bots = try RemoteBots(url: url, code: code, count: 1, ready: true)
        #expect(try await waitUntil(timeout: .seconds(30)) { me.log.last?.players.count == 2 })
        let skipping = me.skipWhenAsked()
        defer { skipping.cancel() }
        await me.session.ready()
        #expect(try await waitUntil(timeout: .seconds(60)) { me.log.last?.phase == .playing })
        #if os(Linux)
        POSIXWebSockets.dropAll()
        #endif
        #expect(try await waitUntil(timeout: .seconds(600)) { me.log.last?.phase == .finished })
        #expect([.defeat, .victory, .draw].contains(me.log.last?.result?.outcome))
        #expect(try await waitUntil { await me.store.results().count == 1 })
        _ = bots
    }
}
