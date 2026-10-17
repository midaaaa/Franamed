//
//  PlaylistsPreview.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import SwiftUI

struct PlaylistsPreview<Content: View>: View {
    @StateObject private var playlists = PlaylistsViewModel()
    @ViewBuilder let content: (PlaylistsViewModel) -> Content

    var body: some View {
        content(playlists)
            .task { await playlists.load() }
    }
}
