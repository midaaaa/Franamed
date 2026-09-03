//
//  FrameVerdict.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct FrameVerdict: Codable, Sendable, Identifiable, Equatable {
    let imageId: Int
    let status: ImageStatus
    let difficultyTier: DifficultyTier?

    var id: Int { imageId }

    init(imageId: Int, status: ImageStatus, difficultyTier: DifficultyTier? = nil) {
        self.imageId = imageId
        self.status = status
        self.difficultyTier = difficultyTier
    }
}
