//
//  CatalogIndexStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

actor CatalogIndexStore {
    private let catalog: BackendCatalogServiceProtocol
    private let latestVersion: @Sendable () -> String?
    private let cache = JSONFileCache<CatalogIndex>(url: URL.cachesDirectory.appending(path: "catalog-index.json"))
    private var index: CatalogIndex?
    private var isCheckedThisLaunch = false

    init(catalog: BackendCatalogServiceProtocol, latestVersion: @escaping @Sendable () -> String?) {
        self.catalog = catalog
        self.latestVersion = latestVersion
    }

    func current() async throws -> CatalogIndex {
        if index == nil {
            index = cache.load()
        }
        if let index, isCheckedThisLaunch, latestVersion().map({ $0 == index.version }) ?? true {
            return index
        }
        return try await refresh()
    }

    @discardableResult
    func refresh() async throws -> CatalogIndex {
        do {
            if let fresh = try await catalog.index(ifNoneMatch: index?.version) {
                index = fresh
                cache.save(fresh)
            }
        } catch {
            guard index != nil else { throw error }
        }
        isCheckedThisLaunch = true
        guard let index else { throw BackendError.invalidResponse }
        return index
    }
}
