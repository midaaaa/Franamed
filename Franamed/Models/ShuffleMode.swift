//
//  ShuffleMode.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

enum ShuffleMode: Hashable, CaseIterable {
    case smart
    case random

    var summary: String {
        switch self {
        case .smart: "Сначала новые, потом те, что были давно."
        case .random: "Выключено — любой подходящий, сыгранный тоже."
        }
    }
}
