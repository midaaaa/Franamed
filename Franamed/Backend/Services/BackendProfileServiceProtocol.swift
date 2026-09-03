//
//  BackendProfileServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendProfileServiceProtocol: Sendable {
    func profile() async throws -> ProfileSnapshot

    func watched(since: Double) async throws -> [WatchedEntry]
    func syncWatched(_ entries: [WatchedEntry]) async throws -> Int
    func resetWatched(source: WatchedSource?) async throws

    func budget() async throws -> AttemptBudget
    func consumeAttempt() async throws -> ConsumeAttemptResult

    func dailyStatus() async throws -> DailyStatus
    func recordDaily(date: String, mediaKey: String, attemptsUsed: Int, wasCorrect: Bool) async throws -> DailyResultOutcome
}

extension BackendProfileServiceProtocol {
    func watched() async throws -> [WatchedEntry] {
        try await watched(since: 0)
    }
}
