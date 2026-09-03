//
//  DifficultyTier.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum DifficultyTier: String, Codable, Sendable, CaseIterable, Identifiable {
    case hard
    case medium
    case easy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hard: "Сложный"
        case .medium: "Средний"
        case .easy: "Лёгкий"
        }
    }
}
