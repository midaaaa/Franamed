//
//  PlaylistCoverCell.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistCoverCell: View {
    let playlist: PlaylistDetail
    let isSelected: Bool
    var addedCount = 0
    var isLifted = false
    var posterOverride: [PlaylistPosterSlot]?
    var hidesPosters = false
    var onFolderFrame: ((CGRect) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            PlaylistFolderCover(content: playlist.folderContent, addedCount: addedCount, isOpen: isLifted, isSelected: isSelected,
                                posterOverride: posterOverride, hidesPosters: hidesPosters)
                .onGlobalFrameChange { onFolderFrame?($0) }
            Text(playlist.title)
                .font(PlaylistStyle.shelfTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if playlist.availableCount == 0 {
                Text("скоро")
                    .font(PlaylistStyle.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
