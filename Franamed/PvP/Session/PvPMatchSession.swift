//
//  PvPMatchSession.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

actor PvPMatchSession: PvPSessionProtocol {
    private let makeTransport: @Sendable () -> any PvPTransport
    private let reducer: any PvPMatchReducer
    private let preloader: any PvPFramePreloader
    private let resultStore: any PvPResultStore
    private let now: @Sendable () -> Date
    private let hub: PvPStateHub

    private let socketURL: URL
    private let ticket: String
    private var resumeToken: String?
    private var welcomed = false

    private var state: PvPMatchState
    private var transport: (any PvPTransport)?
    private var listener: Task<Void, Never>?
    private var generation = 0
    private var timer: Task<Void, Never>?
    private var preload: Task<Void, Never>?
    private var pendingAnswer: PvPClientMessage?
    private var savedResultID: String?

    init(
        room: PvPRoomTicket,
        code: String,
        reducer: any PvPMatchReducer,
        preloader: any PvPFramePreloader,
        resultStore: any PvPResultStore,
        now: @escaping @Sendable () -> Date = { Date() },
        makeTransport: @escaping @Sendable () -> any PvPTransport
    ) {
        self.socketURL = room.socketURL
        self.ticket = room.ticket
        self.reducer = reducer
        self.preloader = preloader
        self.resultStore = resultStore
        self.now = now
        self.makeTransport = makeTransport
        self.state = PvPMatchState(code: code)
        self.hub = PvPStateHub(state)
    }

    // MARK: PvPSessionProtocol

    nonisolated func states() -> AsyncStream<PvPMatchState> {
        hub.stream()
    }

    func connect() async {
        guard transport == nil else { return }
        if case .closed = state.phase, !canReconnect { return }
        await open()
    }

    func disconnect() async {
        guard let transport else { return }
        listener?.cancel()
        listener = nil
        generation += 1
        self.transport = nil
        await transport.close()
        apply(.transport(.closed(.cancelled)))
    }

    func ready() async {
        guard state.phase == .lobby else { return }
        await send(.ready(film: 0))
    }

    func unready() async {
        guard state.phase == .lobby else { return }
        await send(.unready)
    }

    func guess(tmdbId: Int?, mediaType: MediaType, text: String) async {
        guard let (film, frame) = answerableFrame() else { return }
        let message = PvPClientMessage.guess(film: film, frame: frame, tmdbId: tmdbId, mediaType: mediaType,
                                             text: text.isEmpty ? nil : text)
        await answer(message, film: film, frame: frame)
    }

    func skip() async {
        guard let (film, frame) = answerableFrame() else { return }
        await answer(.skip(film: film, frame: frame), film: film, frame: frame)
    }

    func frameBroken(index: Int) async {
        guard let preparation = state.preparation else { return }
        apply(.preparation(film: preparation.film, .broken(index: index)))
        await send(.frameBroken(film: preparation.film, index: index))
    }

    func setAway(_ away: Bool) async {
        if !away { await revive() }
        await send(.away(away))
    }

    func leave() async {
        await send(.leave)
    }

    func changeSettings(films: Int?, frames: Int?, timeLimitSec: Int?) async {
        await send(.settings(films: films, frames: frames, timeLimitSec: timeLimitSec))
    }

    func start() async { await send(.start) }
    func pause() async { await send(.pause) }
    func resume() async { await send(.resume) }
    func kick(uid: String) async { await send(.kick(uid: uid)) }
    func hideName(uid: String) async { await send(.hideName(uid: uid)) }
    func newMatch() async { await send(.newMatch) }

    // MARK: Connection

    private var canReconnect: Bool {
        switch state.phase {
        case .closed(.disconnected), .closed(.failed): true
        case .closed: false
        default: true
        }
    }

    private func open() async {
        let transport = makeTransport()
        self.transport = transport
        generation += 1
        let id = generation
        listener?.cancel()
        listener = Task { [weak self] in
            for await event in transport.events {
                await self?.receive(event, generation: id)
            }
        }
        let credential: PvPCredential = resumeToken.map { .resume($0) } ?? .ticket(ticket)
        await transport.connect(to: socketURL, credential: credential, lastSeq: state.seq >= 0 ? state.seq : nil)
    }

    private func revive() async {
        if transport == nil {
            if resumeToken != nil, canReconnect { await open() }
            return
        }
        guard state.link != .socket, let resumeToken, let transport else { return }
        await transport.connect(to: socketURL, credential: .resume(resumeToken), lastSeq: state.seq >= 0 ? state.seq : nil)
    }

    private func receive(_ event: PvPTransportEvent, generation id: Int) async {
        guard id == generation, transport != nil else { return }

        var reconnected = false
        if case let .message(envelope) = event, case let .welcome(welcome) = envelope.message {
            resumeToken = welcome.you.resumeToken
            reconnected = welcomed
            welcomed = true
        }
        if case .closed = event {
            self.transport = nil
            listener = nil
        }

        let before = state
        apply(.transport(event))
        await react(from: before, reconnected: reconnected)
    }

    // MARK: Reactions

    private func react(from before: PvPMatchState, reconnected: Bool) async {
        if let preparation = state.preparation, preparation.status == .loading,
           before.preparation?.film != preparation.film || before.preparation?.frames != preparation.frames || before.preparation?.status != .loading {
            startPreload(preparation)
        } else if state.preparation == nil {
            preload?.cancel()
        }

        if let pending = pendingAnswer, !stillPending(pending) {
            pendingAnswer = nil
        }
        if reconnected, let pending = pendingAnswer {
            await send(pending)
        }

        if let result = state.result, result.id != savedResultID {
            savedResultID = result.id
            await resultStore.save(result)
        }
    }

    private func startPreload(_ preparation: PvPMatchPreparation) {
        preload?.cancel()
        let preloader = self.preloader
        preload = Task { [weak self] in
            let outcome = await preloader.preload(frames: preparation.frames, spares: preparation.spares)
            guard !Task.isCancelled else { return }
            await self?.preloaded(preparation, outcome: outcome)
        }
    }

    private func preloaded(_ preparation: PvPMatchPreparation, outcome: PvPFramePreload) async {
        guard state.preparation?.film == preparation.film, state.preparation?.frames == preparation.frames else { return }
        switch outcome {
        case .ready:
            apply(.preparation(film: preparation.film, .ready))
            await send(.ready(film: preparation.film))
        case let .broken(index):
            apply(.preparation(film: preparation.film, .broken(index: index)))
            await send(.frameBroken(film: preparation.film, index: index))
        }
    }

    private func answerableFrame() -> (Int, Int)? {
        guard state.phase == .playing, state.pause == nil, let film = state.film, film.resumesAt == nil,
              film.yourStatus == .thinking, !film.answering, let frame = film.yourFrame else { return nil }
        return (film.number, frame)
    }

    private func answer(_ message: PvPClientMessage, film: Int, frame: Int) async {
        pendingAnswer = message
        apply(.answerSent(film: film, frame: frame))
        await send(message)
    }

    private func stillPending(_ message: PvPClientMessage) -> Bool {
        let target: (Int, Int)
        switch message {
        case let .guess(film, frame, _, _, _), let .skip(film, frame): target = (film, frame)
        default: return false
        }
        guard let film = state.film, film.number == target.0, film.yourFrame == target.1, film.yourStatus == .thinking else { return false }
        return film.lastGuess?.frame != target.1
    }

    private func send(_ message: PvPClientMessage) async {
        await transport?.send(message)
    }

    // MARK: State

    private func apply(_ event: PvPMatchEvent) {
        state = reducer.reduce(state, event, now: now())
        hub.publish(state)
        schedule()
    }

    private func schedule() {
        timer?.cancel()
        guard let next = reducer.nextChange(of: state, now: now()) else { return }
        let delay = max(0, next.timeIntervalSince(now()))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 1))
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    private func tick() {
        apply(.tick)
    }
}
