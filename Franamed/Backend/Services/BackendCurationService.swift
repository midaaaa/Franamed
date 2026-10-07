//
//  BackendCurationService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendCurationService: BackendCurationServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func report(imageId: Int, reason: ReportReason) async throws -> CurationReportResult {
        struct Payload: Encodable, Sendable {
            let imageId: Int
            let reason: ReportReason
        }
        return try await client.post("/v1/curation/report", body: Payload(imageId: imageId, reason: reason))
    }

    func updateImage(
        id: Int,
        difficultyTier: DifficultyTier?? = nil,
        difficultyRank: Int?? = nil,
        clusteredWith: String?? = nil,
        perceptualHash: String? = nil,
        status: ImageStatus? = nil
    ) async throws -> CuratedImage {
        struct Payload: Encodable, Sendable {
            var difficultyTier: DifficultyTier??
            var difficultyRank: Int??
            var clusteredWith: String??
            var perceptualHash: String?
            var status: ImageStatus?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let difficultyTier { try container.encode(difficultyTier, forKey: .difficultyTier) }
                if let difficultyRank { try container.encode(difficultyRank, forKey: .difficultyRank) }
                if let clusteredWith { try container.encode(clusteredWith, forKey: .clusteredWith) }
                if let perceptualHash { try container.encode(perceptualHash, forKey: .perceptualHash) }
                if let status { try container.encode(status, forKey: .status) }
            }

            enum CodingKeys: String, CodingKey {
                case difficultyTier, difficultyRank, clusteredWith, perceptualHash, status
            }
        }

        return try await client.patch(
            "/v1/curation/images/\(id)",
            body: Payload(
                difficultyTier: difficultyTier,
                difficultyRank: difficultyRank,
                clusteredWith: clusteredWith,
                perceptualHash: perceptualHash,
                status: status
            )
        )
    }

    func dismissDisputes(imageId: Int) async throws -> CuratedImage {
        try await client.post("/v1/curation/images/\(imageId)/dismiss-disputes")
    }
}
