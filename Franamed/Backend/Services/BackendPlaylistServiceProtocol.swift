//
//  BackendPlaylistServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendPlaylistServiceProtocol: Sendable {
    func playlists(mediaType: MediaType?, includeUnpublished: Bool) async throws -> [Playlist]
    func playlist(id: String) async throws -> PlaylistDetail

    func create(title: String, description: String?, mediaType: MediaType) async throws -> Playlist
    func setPublished(id: String, published: Bool) async throws -> Playlist
    func setItems(id: String, mediaKeys: [String]) async throws

    func recordProgress(id: String, mediaKey: String, attemptsUsed: Int, wasCorrect: Bool) async throws -> PlaylistProgress
    func reset(id: String, mode: PlaylistResetMode) async throws -> PlaylistProgress
}

extension BackendPlaylistServiceProtocol {
    func playlists(mediaType: MediaType?) async throws -> [Playlist] {
        try await playlists(mediaType: mediaType, includeUnpublished: false)
    }
}
