//
//  BackendProfileServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendProfileServiceProtocol: Sendable {
    func profile() async throws -> BackendUser

    func watched(since: Double) async throws -> [WatchedEntry]
    func syncWatched(_ entries: [WatchedEntry]) async throws -> Int
    func resetWatched(source: WatchedSource?) async throws

    func dailyStatus() async throws -> DailyStatus
}

extension BackendProfileServiceProtocol {
    func watched() async throws -> [WatchedEntry] {
        try await watched(since: 0)
    }
}
