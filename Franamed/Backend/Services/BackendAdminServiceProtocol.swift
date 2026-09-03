//
//  BackendAdminServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendAdminServiceProtocol: Sendable {
    func config() async throws -> AppGameConfig
    func updateConfig(_ updates: [String: String]) async throws -> AppGameConfig

    func users() async throws -> [AdminUserSummary]
    func setRole(uid: String, role: UserRole) async throws

    func dailySchedule() async throws -> [ScheduledDaily]
    func scheduleDaily(date: String, mediaKey: String) async throws

    func stats() async throws -> CatalogStats
}
