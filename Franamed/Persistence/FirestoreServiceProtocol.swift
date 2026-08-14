//
//  FirestoreServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol FirestoreServiceProtocol {
    func fetchMovieBackdrops(id: Int) async throws -> [Backdrop]
}
