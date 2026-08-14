//
//  StubFirestoreService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

final class StubFirestoreService: FirestoreServiceProtocol {
    func fetchMovieBackdrops(id: Int) async throws -> [Backdrop] {
        return [.init(filePath: "https://example.com/image.jpg")]
    }
}
