//
//  PvPPreviewSession.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

#if DEBUG
import Foundation

import Synchronization

final class PvPPreviewSession: PvPSessionProtocol {
    struct Step: Sendable {
        let after: Duration
        let state: @Sendable () -> PvPMatchState
    }

    private struct Shared {
        var state: PvPMatchState
        var subscribers: [UUID: AsyncStream<PvPMatchState>.Continuation] = [:]
        var player: Task<Void, Never>?
        var actions: [String] = []
    }

    private let steps: [Step]
    private let loops: Bool
    private let shared: Mutex<Shared>

    init(steps: [Step], loops: Bool = true) {
        self.steps = steps
        self.loops = loops
        self.shared = Mutex(Shared(state: steps.first?.state() ?? PvPMatchState(code: "PREVIEW")))
    }

    convenience init(_ state: PvPMatchState) {
        self.init(steps: [Step(after: .zero, state: { state })], loops: false)
    }

    static func room() -> PvPPreviewSession {
        PvPPreviewSession(steps: PvPMatchFixtures.roomScenario)
    }

    static func duel() -> PvPPreviewSession {
        PvPPreviewSession(steps: PvPMatchFixtures.duelScenario)
    }

    var actions: [String] { shared.withLock { $0.actions } }

    func states() -> AsyncStream<PvPMatchState> {
        let (stream, continuation) = AsyncStream.makeStream(of: PvPMatchState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        shared.withLock { shared in
            shared.subscribers[id] = continuation
            continuation.yield(shared.state)
        }
        continuation.onTermination = { [weak self] _ in
            self?.shared.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        startIfNeeded()
        return stream
    }

    private func startIfNeeded() {
        guard steps.count > 1 else { return }
        let steps = steps
        let loops = loops
        shared.withLock { shared in
            guard shared.player == nil else { return }
            shared.player = Task { [weak self] in
                repeat {
                    for step in steps {
                        try? await Task.sleep(for: step.after)
                        guard !Task.isCancelled else { return }
                        self?.publish(step.state())
                    }
                } while loops && !Task.isCancelled
            }
        }
    }

    private func publish(_ state: PvPMatchState) {
        shared.withLock { shared in
            shared.state = state
            for continuation in shared.subscribers.values { continuation.yield(state) }
        }
    }

    private func record(_ action: String) {
        shared.withLock { $0.actions.append(action) }
    }

    deinit {
        shared.withLock { $0.player?.cancel() }
    }

    // MARK: Actions

    func connect() async { record("connect") }
    func disconnect() async { record("disconnect") }
    func ready() async { record("ready") }
    func unready() async { record("unready") }
    func guess(tmdbId: Int?, mediaType: MediaType, text: String) async { record("guess \(tmdbId.map(String.init) ?? text)") }
    func skip() async { record("skip") }
    func frameBroken(index: Int) async { record("frameBroken \(index)") }
    func setAway(_ away: Bool) async { record("away \(away)") }
    func leave() async { record("leave") }
    func changeSettings(films: Int?, frames: Int?, timeLimitSec: Int?) async { record("settings") }
    func start() async { record("start") }
    func pause() async { record("pause") }
    func resume() async { record("resume") }
    func kick(uid: String) async { record("kick \(uid)") }
    func hideName(uid: String) async { record("hideName \(uid)") }
    func newMatch() async { record("newMatch") }
}
#endif
