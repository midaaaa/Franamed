//
//  UserRole.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum UserRole: String, Codable, Sendable, CaseIterable, Comparable {
    case user
    case moderator
    case admin

    private var rank: Int {
        switch self {
        case .user: 0
        case .moderator: 1
        case .admin: 2
        }
    }

    static func < (lhs: UserRole, rhs: UserRole) -> Bool { lhs.rank < rhs.rank }

    var displayName: String {
        switch self {
        case .user: "Игрок"
        case .moderator: "Модератор"
        case .admin: "Админ"
        }
    }
}
