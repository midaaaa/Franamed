//
//  PendingFinish.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

struct PendingFinish: Codable, Sendable {
    let mediaKey: String
    let frameCount: Int
    let solvedAtFrame: Int?
    let playedAt: Date
}
