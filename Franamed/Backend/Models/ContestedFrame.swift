//
//  ContestedFrame.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct ContestedFrame: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let mediaKey: String
    let filePath: String
    let status: ImageStatus
    let reportWeight: Double
    let difficultyTier: DifficultyTier?
    let moderatorStatus: ImageStatus?
    let moderatorAt: Double?
    let disputesDismissedCount: Int
    let title: String
    let releaseYear: Int?
    let reportCount: Int
    let shadowApproveWeight: Double
    let shadowRejectWeight: Double

    var disagreement: Double { shadowRejectWeight - shadowApproveWeight }

    func imageURL(imageBaseURL: String) -> URL? {
        URL(string: "\(imageBaseURL)/t/p/w1280\(filePath)")
    }
}
