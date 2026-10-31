//
//  PvPSocketTransport.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

actor PvPSocketTransport: PvPTransport {
    nonisolated let events: AsyncStream<PvPTransportEvent>
    private let continuation: AsyncStream<PvPTransportEvent>.Continuation
    private let session: URLSession
    private let sockets: any PvPWebSocketFactory
    private let timing: PvPTransportTiming
    private let clock = ContinuousClock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var socketURL: URL?
    private var credential: PvPCredential?
    private var lastSeq: Int?
    private var link: PvPLinkMode = .connecting
    private var isFinished = false

    private var socket: (any PvPWebSocket)?
    private var generation = 0
    private var socketOpen = false
    private var failures = 0
    private var lastHeard: ContinuousClock.Instant
    private var socketTasks: [Task<Void, Never>] = []

    private var outbox: [PvPClientMessage] = []
    private var bucket: PvPSendBucket
    private var pumping = false

    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pollPaused = false
    private var pollInFlight = false
    private var napper: CheckedContinuation<Void, Never>?
    private var napTimer: Task<Void, Never>?

    init(session: URLSession = .shared, sockets: (any PvPWebSocketFactory)? = nil, timing: PvPTransportTiming = .default) {
        (events, continuation) = AsyncStream.makeStream(of: PvPTransportEvent.self)
        self.session = session
        self.sockets = sockets ?? PvPURLSessionWebSockets(session: session)
        self.timing = timing
        self.lastHeard = clock.now
        self.bucket = PvPSendBucket(capacity: timing.burst, refill: timing.refill, now: clock.now)
    }

    // MARK: PvPTransport

    func connect(to socketURL: URL, credential: PvPCredential, lastSeq: Int?) {
        guard !isFinished else { return }
        self.socketURL = socketURL
        self.credential = credential
        self.lastSeq = lastSeq
        failures = 0
        stopPolling()
        continuation.yield(.link(.connecting))
        link = .connecting
        openSocket()
    }

    func send(_ message: PvPClientMessage) {
        guard !isFinished else { return }
        outbox.append(message)
        if link == .polling {
            wakeUp()
        } else if socketOpen {
            Task { await pump() }
        }
    }

    func close() {
        guard !isFinished else { return }
        socket?.close(code: 1000)
        socket = nil
        finish(.cancelled)
    }

    // MARK: Socket

    private func openSocket() {
        guard let socketURL, let credential, !isFinished else { return }
        dropSocket()
        generation += 1
        let id = generation

        var components = URLComponents(url: socketURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "lastSeq", value: lastSeq.map(String.init) ?? "")]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("PvP \(credential.token)", forHTTPHeaderField: "Authorization")
        let task = sockets.open(request)
        socket = task
        socketOpen = false
        lastHeard = clock.now

        let timeout = timing.connectTimeout
        socketTasks = [
            Task { await self.receive(from: task, generation: id) },
            Task {
                try? await Task.sleep(for: timeout)
                self.abandonIfStillOpening(generation: id)
            }
        ]
    }

    private func dropSocket() {
        socketTasks.forEach { $0.cancel() }
        socketTasks = []
        socket?.close(code: 1001)
        socket = nil
        socketOpen = false
    }

    private func abandonIfStillOpening(generation id: Int) {
        guard id == generation, !socketOpen else { return }
        socket?.close(code: 1001)
    }

    private func receive(from task: any PvPWebSocket, generation id: Int) async {
        while true {
            switch await task.receive() {
            case let .text(text):
                guard id == generation, !isFinished else { return }
                lastHeard = clock.now
                handle(Data(text.utf8), viaSocket: true)
            case let .closed(code, reason, status):
                await socketFailed(code: code, reason: reason, status: status, generation: id)
                return
            }
        }
    }

    private func socketOpened() {
        socketOpen = true
        failures = 0
        stopPolling()
        setLink(.socket)

        let id = generation
        let ping = timing.ping
        socketTasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: ping)
                guard await self.keepAlive(generation: id) else { return }
            }
        })
        Task { await pump() }
    }

    private func keepAlive(generation id: Int) async -> Bool {
        guard id == generation, socketOpen, let socket, !isFinished else { return false }
        if clock.now - lastHeard > timing.silence {
            socket.close(code: 1001)
            return false
        }
        try? await socket.send(#"{"t":"ping"}"#)
        return true
    }

    private func socketFailed(code: Int?, reason: String?, status: Int?, generation id: Int) async {
        guard id == generation, !isFinished else { return }
        let wasOpen = socketOpen
        dropSocket()

        if let code, let closeCode = PvPCloseCode(rawValue: code), !closeCode.allowsReconnect {
            finish(.socket(code: code, reason: reason))
            return
        }
        if !wasOpen, let status, let refusal = Self.refusal(status: status) {
            finish(.refused(status: status, code: refusal))
            return
        }
        if link == .polling {
            pollPaused = false
            wakeUp()
            scheduleSocketRetry()
            return
        }

        if !wasOpen { failures += 1 }
        let canPoll: Bool
        if case .resume = credential { canPoll = true } else { canPoll = false }

        if canPoll && failures >= timing.failuresBeforePolling {
            startPolling()
            return
        }
        if !canPoll && failures >= timing.attemptsWithoutResume {
            finish(.refused(status: status ?? 0, code: "connect_failed"))
            return
        }

        setLink(.reconnecting)
        try? await Task.sleep(for: timing.reconnectDelay * max(1, failures))
        guard !isFinished, link == .reconnecting, socket == nil else { return }
        openSocket()
    }

    // MARK: Outbox

    private func pump() async {
        guard !pumping else { return }
        pumping = true
        defer { pumping = false }

        while let message = outbox.first, !isFinished, socketOpen, let task = socket {
            let wait = bucket.delay(at: clock.now)
            if wait > .zero {
                try? await Task.sleep(for: wait)
                continue
            }
            guard let text = encode(message) else {
                outbox.removeFirst()
                continue
            }
            _ = bucket.take(at: clock.now)
            do {
                try await task.send(text)
            } catch {
                return
            }
            if outbox.first == message { outbox.removeFirst() }
        }
    }

    private func takeSendable() -> [PvPClientMessage] {
        var taken: [PvPClientMessage] = []
        while let message = outbox.first, taken.count < timing.burst, bucket.take(at: clock.now) {
            taken.append(message)
            outbox.removeFirst()
        }
        return taken
    }

    private func encode(_ message: PvPClientMessage) -> String? {
        guard let data = try? encoder.encode(message) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Polling

    private struct Refusal: Decodable {
        let error: String
    }

    private enum PollResult {
        case messages([PvPEnvelope])
        case refused(status: Int, code: String)
        case failed
    }

    private func startPolling() {
        failures = 0
        pollPaused = false
        setLink(.polling)
        pollTask?.cancel()
        pollTask = Task { await pollLoop() }
        scheduleSocketRetry()
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        retryTask?.cancel()
        retryTask = nil
        pollPaused = false
        wakeUp()
    }

    private func pollLoop() async {
        var nextPoll = clock.now
        while !Task.isCancelled, !isFinished, link == .polling {
            if pollPaused {
                await nap(until: clock.now + timing.socketRetry)
                continue
            }
            let sending = takeSendable()
            if sending.isEmpty && clock.now < nextPoll {
                let wake = outbox.isEmpty ? nextPoll : min(nextPoll, clock.now + bucket.delay(at: clock.now))
                await nap(until: wake)
                continue
            }

            nextPoll = clock.now + timing.poll
            pollInFlight = true
            let result = await postPoll(sending)
            pollInFlight = false

            switch result {
            case let .messages(envelopes):
                for envelope in envelopes { deliver(envelope, viaSocket: false) }
                if sending.contains(.leave) {
                    finish(.socket(code: PvPCloseCode.left.rawValue, reason: "left"))
                }
            case let .refused(status, code):
                finish(.refused(status: status, code: code))
            case .failed:
                outbox.insert(contentsOf: sending, at: 0)
            }
        }
    }

    private func postPoll(_ messages: [PvPClientMessage]) async -> PollResult {
        guard let pollURL, case let .resume(token)? = credential,
              let body = try? encoder.encode(PvPPollRequest(lastSeq: lastSeq ?? -1, send: messages)) else {
            return .failed
        }
        var request = URLRequest(url: pollURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timing.pollTimeout.timeInterval
        request.setValue("PvP \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        if (200...299).contains(http.statusCode) {
            guard let poll = try? decoder.decode(PvPPoll.self, from: data) else { return .failed }
            return .messages(poll.messages)
        }
        guard let fallback = Self.refusal(status: http.statusCode) else { return .failed }
        let code = (try? decoder.decode(Refusal.self, from: data))?.error ?? fallback
        return .refused(status: http.statusCode, code: code)
    }

    private var pollURL: URL? {
        guard let socketURL, var components = URLComponents(url: socketURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "wss" ? "https" : components.scheme == "ws" ? "http" : components.scheme
        components.path = (components.path as NSString).deletingLastPathComponent + "/poll"
        components.query = nil
        return components.url
    }

    private func scheduleSocketRetry() {
        retryTask?.cancel()
        let delay = timing.socketRetry
        retryTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.probeSocket()
        }
    }

    private func probeSocket() async {
        guard link == .polling, !isFinished else { return }
        pollPaused = true
        wakeUp()
        while pollInFlight {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard link == .polling, !isFinished else { return }
        openSocket()
    }

    private func nap(until deadline: ContinuousClock.Instant) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            napper = continuation
            napTimer = Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                self.wakeUp()
            }
        }
    }

    private func wakeUp() {
        napTimer?.cancel()
        napTimer = nil
        napper?.resume()
        napper = nil
    }

    // MARK: Delivery

    private func handle(_ data: Data, viaSocket: Bool) {
        guard let envelope = try? decoder.decode(PvPEnvelope.self, from: data) else { return }
        deliver(envelope, viaSocket: viaSocket)
    }

    private func deliver(_ envelope: PvPEnvelope, viaSocket: Bool) {
        guard !isFinished else { return }
        if case .pong = envelope.message { return }
        if let seq = envelope.seq { lastSeq = max(lastSeq ?? -1, seq) }
        if case let .welcome(welcome) = envelope.message {
            credential = .resume(welcome.you.resumeToken)
            lastSeq = max(lastSeq ?? -1, welcome.seq)
            if viaSocket && !socketOpen { socketOpened() }
        }
        continuation.yield(.message(envelope))
    }

    private func setLink(_ mode: PvPLinkMode) {
        guard link != mode else { return }
        link = mode
        continuation.yield(.link(mode))
    }

    private func finish(_ closure: PvPTransportClosure) {
        guard !isFinished else { return }
        isFinished = true
        dropSocket()
        stopPolling()
        continuation.yield(.closed(closure))
        continuation.finish()
    }

    private static func refusal(status: Int) -> String? {
        switch status {
        case 401: "token_invalid"
        case 403: "kicked"
        case 404: "room_not_found"
        case 409: "room_full"
        default: nil
        }
    }
}

private extension PvPCredential {
    var token: String {
        switch self {
        case let .ticket(token), let .resume(token): token
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
