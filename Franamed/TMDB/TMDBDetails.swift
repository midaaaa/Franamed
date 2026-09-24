//
//  TMDBDetails.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import Foundation

private struct DetailsResponse: Decodable {
    struct Named: Decodable { let name: String }
    struct CrewMember: Decodable { let name: String; let job: String? }
    struct Credits: Decodable { let crew: [CrewMember]? }
    struct ReleaseDate: Decodable { let certification: String?; let type: Int? }
    struct CountryReleases: Decodable { let iso31661: String; let releaseDates: [ReleaseDate] }
    struct ReleaseDates: Decodable { let results: [CountryReleases] }
    struct ContentRating: Decodable { let iso31661: String; let rating: String? }
    struct ContentRatings: Decodable { let results: [ContentRating] }

    let runtime: Int?
    let releaseDate: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let numberOfSeasons: Int?
    let inProduction: Bool?
    let status: String?
    let createdBy: [Named]?
    let credits: Credits?
    let releaseDates: ReleaseDates?
    let contentRatings: ContentRatings?
}

extension TMDBClient {
    func fetchDetails(mediaType: MediaType, id: Int) async throws -> MediaDetails {
        let appended = mediaType == .movie
            ? "credits,release_dates"
            : "content_ratings"

        let response: DetailsResponse = try await get(
            path: "/3/\(mediaType.rawValue)/\(id)",
            query: [
                URLQueryItem(name: "language", value: "ru-RU"),
                URLQueryItem(name: "append_to_response", value: appended)
            ]
        )

        var details = MediaDetails()
        details.runtimeMinutes = response.runtime
        details.firstYear = Self.year(from: response.releaseDate ?? response.firstAirDate)
        details.lastYear = Self.year(from: response.lastAirDate)
        details.seasonCount = response.numberOfSeasons
        details.isInProduction = response.inProduction ?? false
        details.isCanceled = response.status == "Canceled"
        details.certification = Self.certification(from: response)
        details.authors = mediaType == .movie
            ? (response.credits?.crew ?? []).filter { $0.job == "Director" }.prefix(2).map(\.name)
            : (response.createdBy ?? []).prefix(2).map(\.name)

        return details
    }

    private static func year(from date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    private static func certification(from response: DetailsResponse) -> String? {
        let region = Locale.current.region?.identifier ?? "US"

        if let countries = response.releaseDates?.results {
            let mine = countries.first { $0.iso31661 == region }?.releaseDates ?? []
            let theatrical = mine.first { $0.type == 3 }?.certification
            let any = mine.compactMap(\.certification).first { !$0.isEmpty }
            return normalized(theatrical ?? any)
        }

        if let ratings = response.contentRatings?.results {
            return normalized(ratings.first { $0.iso31661 == region }?.rating)
        }

        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "NR" else { return nil }
        return value
    }
}
