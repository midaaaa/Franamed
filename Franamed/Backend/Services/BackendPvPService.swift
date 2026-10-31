//
//  BackendPvPService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

final class BackendPvPService: PvPServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func profile() async throws -> PvPProfile {
        try await client.get("/v1/pvp/profile")
    }

    func updateProfile(_ update: PvPProfileUpdate) async throws -> PvPProfile {
        try await client.patch("/v1/pvp/profile", body: update)
    }

    func createRoom(_ room: PvPCreateRoom) async throws -> PvPRoomTicket {
        try await client.post("/v1/pvp/rooms", body: room)
    }

    func ticket(code: String) async throws -> PvPRoomTicket {
        guard let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw BackendError.invalidURL
        }
        return try await client.post("/v1/pvp/rooms/\(escaped)/ticket")
    }
}
