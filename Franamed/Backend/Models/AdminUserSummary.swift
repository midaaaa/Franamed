//
//  AdminUserSummary.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct AdminUserSummary: Codable, Sendable, Identifiable {
    let uid: String
    let role: UserRole
    let displayName: String?
    let isAnonymous: Bool
    let createdAt: Double
    let dailyStreak: Int

    var id: String { uid }
}
