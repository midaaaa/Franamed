//
//  CuratedImage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CuratedImage: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let mediaKey: String
    let filePath: String
    let status: ImageStatus
    let reportWeight: Double
    let perceptualHash: String?
    let clusteredWith: String?
    let difficultyTier: DifficultyTier?
    let difficultyRank: Int?

    let moderatorStatus: ImageStatus?
    let moderatorAt: Double?
    let disputesDismissedCount: Int
    let voteAverage: Double
    let voteCount: Int
    let width: Int?
    let height: Int?
    let aspectRatio: Double?

    func backdrop(imageBaseURL: String) -> Backdrop {
        Backdrop(filePath: "\(imageBaseURL)/t/p/w1280\(filePath)")
    }
}
