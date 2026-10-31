//
//  PvPEntryViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Combine
import Foundation

struct PvPRoomRoute: Identifiable, Equatable {
    let code: String
    let ticket: PvPRoomTicket

    var id: String { code }
}

@MainActor
final class PvPEntryViewModel: ObservableObject {
    enum Busy: Equatable {
        case creating(PvPRoomKind)
        case joining
        case saving
    }

    @Published private(set) var profile: PvPProfile?
    @Published private(set) var busy: Busy?
    @Published private(set) var error: String?
    @Published var code = "" {
        didSet {
            let typed = PvPRoomLink.typed(code)
            if typed != code { code = typed }
        }
    }
    @Published var room: PvPRoomRoute?

    let mediaType: MediaType
    private let service: any PvPServiceProtocol

    init(service: any PvPServiceProtocol, mediaType: MediaType = .movie) {
        self.service = service
        self.mediaType = mediaType
    }

    var canJoin: Bool { PvPRoomLink.isValid(code) && busy == nil }

    var avatar: PvPAvatar? { profile.map { PvPAvatar(icon: $0.icon, color: $0.color) } }

    func load() async {
        guard profile == nil else { return }
        await run { self.profile = try await self.service.profile() }
    }

    func create(_ kind: PvPRoomKind) async {
        guard busy == nil else { return }
        busy = .creating(kind)
        defer { busy = nil }
        await run {
            let ticket = try await self.service.createRoom(PvPCreateRoom(kind: kind, mediaType: self.mediaType))
            guard let code = ticket.code else { throw BackendError.invalidResponse }
            self.room = PvPRoomRoute(code: code, ticket: ticket)
        }
    }

    func join() async {
        await join(code: code)
    }

    func join(code: String) async {
        guard busy == nil, let link = PvPRoomLink(code: code) else { return }
        self.code = link.code
        busy = .joining
        defer { busy = nil }
        await run {
            let ticket = try await self.service.ticket(code: link.code)
            self.room = PvPRoomRoute(code: link.code, ticket: ticket)
        }
    }

    func paste(_ text: String) {
        if let link = PvPRoomLink(text: text) { code = link.code }
    }

    func update(_ update: PvPProfileUpdate) async -> Bool {
        guard busy == nil else { return false }
        busy = .saving
        defer { busy = nil }
        return await run { self.profile = try await self.service.updateProfile(update) }
    }

    func dismissError() {
        error = nil
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
