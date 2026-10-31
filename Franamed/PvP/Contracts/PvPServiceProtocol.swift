//
//  PvPServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

protocol PvPServiceProtocol: Sendable {
    func profile() async throws -> PvPProfile
    func updateProfile(_ update: PvPProfileUpdate) async throws -> PvPProfile

    func createRoom(_ room: PvPCreateRoom) async throws -> PvPRoomTicket
    func ticket(code: String) async throws -> PvPRoomTicket
}
