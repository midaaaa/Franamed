//
//  PlaylistPickerSheet.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistSheetRoute: Identifiable {
    let id = UUID()
    let mediaType: MediaType
    let fromPoster: Bool
    var openedID: String?
}

struct PlaylistPickerSheet: UIViewControllerRepresentable {
    let playlists: PlaylistsViewModel
    let mediaType: MediaType
    var openedID: String?
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> PlaylistNavigationController {
        PlaylistNavigationController(playlists: playlists, mediaType: mediaType, openedID: openedID, onDone: onDone)
    }

    func updateUIViewController(_ controller: PlaylistNavigationController, context: Context) {
    }
}

#Preview("Полка") {
    PlaylistsPreview { playlists in
        PlaylistPickerSheet(playlists: playlists, mediaType: .movie, onDone: {})
            .ignoresSafeArea()
    }
}
