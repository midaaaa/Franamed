//
//  PlaylistEntryState.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum PlaylistEntryState: String, Codable, Sendable {
    case notStarted
    case inProgress
    case completed
}
