//
//  PlayedTitle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

struct PlayedTitle: Codable, Sendable {
    let isHidden: Bool
    let lastPlayedAt: Date
}
