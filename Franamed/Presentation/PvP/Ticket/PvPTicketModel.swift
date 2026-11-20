//
//  PvPTicketModel.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import Combine
import Foundation

/// Drives the PvP ticket on the main screen: the empty Room/Duel faces, joining by code,
/// and the room lobby itself. The match session lives here, so the lobby stays on the ticket
/// and only the match is presented over it.
@MainActor
final class PvPTicketModel: ObservableObject {
    enum Busy: Equatable {
        case creating
        case joining
        case saving
    }

    @Published var kind: PvPRoomKind = .room
    @Published var films = PvPRoomChoices.films[0]
    @Published var frames = PvPRoomChoices.frames[0]
    @Published var timeLimit = PvPRoomChoices.timeLimits[0]
    @Published var code = "" {
        didSet {
            let typed = PvPRoomLink.typed(code)
            if typed != code { code = typed }
        }
    }
    @Published private(set) var busy: Busy?
    @Published var error: String?
    @Published private(set) var profile: PvPProfile?
    @Published private(set) var room: PvPMatchViewModel?
    @Published private(set) var phase: PvPMatchPhase?
    /// The code field has the keyboard; the main screen lifts the ticket above it.
    @Published var isEnteringCode = false

    private let service: any PvPServiceProtocol
    private let makeSession: (PvPRoomTicket, String) -> any PvPSessionProtocol
    private var runTask: Task<Void, Never>?
    private var phaseWatch: AnyCancellable?

    init(service: any PvPServiceProtocol = AppFactory.makePvPService(),
         makeSession: @escaping (PvPRoomTicket, String) -> any PvPSessionProtocol = AppFactory.makePvPSession) {
        self.service = service
        self.makeSession = makeSession
    }

    /// The app's model. In debug builds `PVP_PREVIEW=1` swaps the backend for the scripted preview match.
    static func forApp() -> PvPTicketModel {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PVP_PREVIEW"] == "1" {
            return PvPTicketModel(service: PvPPreviewService(), makeSession: PvPPreview.session)
        }
        #endif
        return PvPTicketModel()
    }

    var avatar: PvPAvatar? { profile.map { PvPAvatar(icon: $0.icon, color: $0.color) } }

    /// The match runs in the hall; the lobby (and a finished room's "new match") stays on the ticket.
    var isInMatch: Bool {
        switch phase {
        case .loading?, .ready?, .countdown?, .playing?, .reveal?, .finished?: true
        default: false
        }
    }

    var closure: PvPMatchClosure? {
        if case let .closed(closure)? = phase { return closure }
        return nil
    }

    // MARK: Profile

    func loadProfile() async {
        guard profile == nil else { return }
        await run { self.profile = try await self.service.profile() }
    }

    func update(_ update: PvPProfileUpdate) async -> Bool {
        guard busy == nil else { return false }
        busy = .saving
        defer { busy = nil }
        return await run { self.profile = try await self.service.updateProfile(update) }
    }

    // MARK: Rooms

    func create(mediaType: MediaType) async {
        guard busy == nil, room == nil else { return }
        busy = .creating
        defer { busy = nil }
        let request = PvPCreateRoom(kind: kind, mediaType: mediaType,
                                    films: kind == .room ? films : nil, frames: frames, timeLimitSec: timeLimit)
        await run {
            let ticket = try await self.service.createRoom(request)
            guard let code = ticket.code else { throw BackendError.invalidResponse }
            self.enter(ticket, code: code)
        }
    }

    func join() async {
        await join(code: code)
    }

    func join(code: String) async {
        guard busy == nil, let link = PvPRoomLink(code: code) else { return }
        if room != nil { await leave() }
        self.code = link.code
        busy = .joining
        defer { busy = nil }
        await run {
            let ticket = try await self.service.ticket(code: link.code)
            self.enter(ticket, code: link.code)
        }
    }

    func paste(_ text: String) {
        if let link = PvPRoomLink(text: text) { code = link.code }
    }

    func leave() async {
        guard let room else { return }
        await room.leave(.leave)
        close()
    }

    /// Drops a finished or closed room without telling the server anything more.
    func close() {
        runTask?.cancel()
        runTask = nil
        phaseWatch = nil
        room = nil
        phase = nil
        code = ""
    }

    func dismissError() {
        error = nil
    }

    private func enter(_ ticket: PvPRoomTicket, code: String) {
        let room = PvPMatchViewModel(session: makeSession(ticket, code), code: code)
        self.room = room
        phase = room.state.phase
        phaseWatch = room.$state
            .map(\.phase)
            .removeDuplicates()
            .sink { [weak self] phase in self?.phase = phase }
        runTask = Task { await room.run() }
    }

    @discardableResult
    private func run(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            error = nil
            return true
        } catch let failure as BackendError {
            if case let .api(_, code, _) = failure {
                error = PvPErrorText.message(code: code)
            } else {
                error = failure.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        return false
    }
}
