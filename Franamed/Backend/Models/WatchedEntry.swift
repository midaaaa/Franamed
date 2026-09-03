//
//  WatchedEntry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct WatchedEntry: Codable, Sendable, Identifiable, Equatable {
    let mediaKey: String
    let sources: [WatchedSource]
    let addedAt: Double

    var id: String { mediaKey }
}
