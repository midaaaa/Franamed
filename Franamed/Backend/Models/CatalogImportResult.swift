//
//  CatalogImportResult.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CatalogImportResult: Codable, Sendable {
    let imported: [ImportedTitle]
    let failed: [FailedImport]

    struct ImportedTitle: Codable, Sendable, Identifiable {
        let key: String
        let importedImages: Int
        let posterPath: String?

        var id: String { key }
    }

    struct FailedImport: Codable, Sendable, Identifiable {
        let tmdbId: Int
        let reason: String

        var id: Int { tmdbId }
    }
}
