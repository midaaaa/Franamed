//
//  PvPStateHub.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation
import Synchronization

final class PvPStateHub: Sendable {
    private struct Hub {
        var state: PvPMatchState
        var subscribers: [UUID: AsyncStream<PvPMatchState>.Continuation] = [:]
    }

    private let hub: Mutex<Hub>

    init(_ state: PvPMatchState) {
        hub = Mutex(Hub(state: state))
    }

    var state: PvPMatchState { hub.withLock { $0.state } }

    func stream() -> AsyncStream<PvPMatchState> {
        let (stream, continuation) = AsyncStream.makeStream(of: PvPMatchState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        hub.withLock { hub in
            hub.subscribers[id] = continuation
            continuation.yield(hub.state)
        }
        continuation.onTermination = { [weak self] _ in
            self?.hub.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    func publish(_ state: PvPMatchState) {
        hub.withLock { hub in
            guard hub.state != state else { return }
            hub.state = state
            for continuation in hub.subscribers.values { continuation.yield(state) }
        }
    }
}
