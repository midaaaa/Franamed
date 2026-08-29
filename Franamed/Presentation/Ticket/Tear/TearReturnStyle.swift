//
//  TearReturnStyle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

nonisolated enum TearReturnStyle: String, Sendable, Equatable, CaseIterable, Identifiable {
    case curled, flat, zip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curled: "Завиток"
        case .flat: "Плоско"
        case .zip: "Молния"
        }
    }
}
