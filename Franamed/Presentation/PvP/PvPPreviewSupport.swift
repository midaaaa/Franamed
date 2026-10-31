//
//  PvPPreviewSupport.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

#if DEBUG
import SwiftUI

struct PvPPreviewService: PvPServiceProtocol {
    var failure: String?

    func profile() async throws -> PvPProfile {
        PvPProfile(uid: PvPMatchFixtures.you, name: "NoirGaffer", customName: false, alias: "HiddenNoirGa", icon: "popcorn", color: "red")
    }

    func updateProfile(_ update: PvPProfileUpdate) async throws -> PvPProfile {
        let name = update.reroll == true ? "MidnightReel" : update.name ?? "NoirGaffer"
        return PvPProfile(uid: PvPMatchFixtures.you, name: name, customName: update.name != nil, alias: "HiddenNoirGa",
                          icon: update.icon ?? "popcorn", color: update.color ?? "red")
    }

    func createRoom(_ room: PvPCreateRoom) async throws -> PvPRoomTicket {
        try await Task.sleep(for: .milliseconds(400))
        if let failure { throw BackendError.api(status: 503, code: failure, message: failure) }
        return PvPRoomTicket(code: room.kind == .duel ? PvPMatchFixtures.duelCode : PvPMatchFixtures.roomCode, ticket: "preview", socketURL: URL(string: "wss://preview")!)
    }

    func ticket(code: String) async throws -> PvPRoomTicket {
        try await Task.sleep(for: .milliseconds(400))
        if let failure { throw BackendError.api(status: 404, code: failure, message: failure) }
        return PvPRoomTicket(code: nil, ticket: "preview", socketURL: URL(string: "wss://preview")!)
    }
}

enum PvPPreview {
    static func session(_ ticket: PvPRoomTicket, code: String) -> any PvPSessionProtocol {
        code == PvPMatchFixtures.duelCode ? PvPPreviewSession.duel() : PvPPreviewSession.room()
    }

    static func screen(_ state: PvPMatchState, options: PvPScreenOptions = PvPScreenOptions()) -> PvPScreen {
        PvPScreen(state: state, now: Date(), options: options)
    }

    static func lobby(_ state: PvPMatchState) -> PvPLobbyScreen? {
        if case let .lobby(lobby) = screen(state).content { return lobby }
        return nil
    }

    static func match(_ state: PvPMatchState) -> PvPMatchScreen? {
        if case let .match(match) = screen(state).content { return match }
        return nil
    }

    static func reveal(_ state: PvPMatchState) -> PvPRevealScreen? {
        if case let .reveal(reveal) = screen(state).content { return reveal }
        return nil
    }

    static func final(_ state: PvPMatchState) -> PvPFinalScreen? {
        if case let .final(final) = screen(state).content { return final }
        return nil
    }

    static func closed(_ state: PvPMatchState) -> PvPClosedScreen? {
        if case let .closed(closed) = screen(state).content { return closed }
        return nil
    }
}
#endif
