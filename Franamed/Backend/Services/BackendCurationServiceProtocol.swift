//
//  BackendCurationServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendCurationServiceProtocol: Sendable {
    func report(imageId: Int, reason: ReportReason) async throws -> CurationReportResult

    func updateImage(
        id: Int,
        difficultyTier: DifficultyTier??,
        difficultyRank: Int??,
        clusteredWith: String??,
        perceptualHash: String?,
        status: ImageStatus?
    ) async throws -> CuratedImage

    func dismissDisputes(imageId: Int) async throws -> CuratedImage
}

