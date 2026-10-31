//
//  PvPFramePreloader.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPFramePreload: Sendable, Equatable {
    case ready
    case broken(index: Int)
}

protocol PvPFramePreloader: Sendable {
    func preload(frames: [PvPFrame], spares: [PvPFrame]) async -> PvPFramePreload
}
