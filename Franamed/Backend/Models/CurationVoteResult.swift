//
//  CurationVoteResult.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CurationVoteResult: Codable, Sendable {
    let images: [CuratedImage]
    let awardedAttempts: Int

    let voteWeight: Double
    let voteCounts: Bool
}
