//
//  PvPReplayTransport.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

#if DEBUG
import Foundation

actor PvPReplayTransport: PvPTransport {
    nonisolated let events: AsyncStream<PvPTransportEvent>
    private let continuation: AsyncStream<PvPTransportEvent>.Continuation
    private let lines: [PvPRecordedTraffic.Line]
    private let speed: Double
    private var player: Task<Void, Never>?
    private(set) var sent: [PvPClientMessage] = []

    init(traffic: String, speed: Double = 1) {
        (events, continuation) = AsyncStream.makeStream(of: PvPTransportEvent.self)
        self.lines = PvPRecordedTraffic.lines(traffic)
        self.speed = max(speed, 0.01)
    }

    func connect(to socketURL: URL, credential: PvPCredential, lastSeq: Int?) {
        guard player == nil else { return }
        player = Task { await play() }
    }

    func send(_ message: PvPClientMessage) {
        sent.append(message)
    }

    func close() {
        player?.cancel()
        continuation.yield(.closed(.cancelled))
        continuation.finish()
    }

    private func play() async {
        continuation.yield(.link(.connecting))
        let clock = ContinuousClock()
        let start = clock.now
        for line in lines {
            try? await Task.sleep(until: start + .milliseconds(Int(line.at / speed)), clock: clock)
            guard !Task.isCancelled else { return }
            if line.reconnect == true {
                continuation.yield(.link(.reconnecting))
            }
            guard let envelope = line.msg else { continue }
            if case .pong = envelope.message { continue }
            continuation.yield(.message(envelope))
            if case .welcome = envelope.message { continuation.yield(.link(.socket)) }
        }
    }
}
#endif
