//
//  BackendCurationServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendCurationServiceProtocol: Sendable {
    func queue(mediaType: MediaType?, limit: Int) async throws -> [CurationQueueEntry]

    func vote(imageId: Int, approve: Bool) async throws -> CurationVoteResult

    func report(imageId: Int, reason: ReportReason) async throws -> CurationReportResult

    func updateImage(
        id: Int,
        difficultyTier: DifficultyTier??,
        difficultyRank: Int??,
        clusteredWith: String??,
        perceptualHash: String?,
        status: ImageStatus?
    ) async throws -> CuratedImage

    func reports(limit: Int) async throws -> [CurationReportEntry]

    func lock(imageId: Int, status: ImageStatus?, difficultyTier: DifficultyTier??) async throws -> CuratedImage

    func contested(limit: Int) async throws -> [ContestedFrame]

    func dismissDisputes(imageId: Int) async throws -> CuratedImage
}

extension BackendCurationServiceProtocol {
    func queue(mediaType: MediaType?) async throws -> [CurationQueueEntry] {
        try await queue(mediaType: mediaType, limit: 20)
    }

    func contested() async throws -> [ContestedFrame] {
        try await contested(limit: 50)
    }

    func reports() async throws -> [CurationReportEntry] {
        try await reports(limit: 50)
    }

    func lock(imageId: Int, status: ImageStatus?) async throws -> CuratedImage {
        try await lock(imageId: imageId, status: status, difficultyTier: nil)
    }
}
