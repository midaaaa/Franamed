//
//  PlaylistPosterFan.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import SwiftUI

struct PlaylistPosterFan: View {
    let posters: [URL?]
    var isHidden = false
    var zoom: CGFloat = 1

    static let mainWidth: CGFloat = 112
    private static let cornerRadius: CGFloat = 8

    static func cornerRadius(posterWidth: CGFloat) -> CGFloat {
        cornerRadius * posterWidth / mainWidth
    }

    var body: some View {
        let layout = Self.layout(count: min(posters.count, PlaylistFolderCover.posterCount), zoom: zoom)
        ZStack {
            ForEach(layout.slots.indices.reversed(), id: \.self) { index in
                let slot = layout.slots[index]
                CachedRemoteImage(url: posters[index])
                    .frame(width: slot.size.width, height: slot.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius(posterWidth: slot.size.width)))
                    .animation(.easeOut(duration: 0.35)) {
                        $0.shadow(color: .black.opacity(isHidden ? 0 : 0.3), radius: 10, y: 6)
                    }
                    .rotationEffect(.degrees(slot.angle), anchor: .bottom)
                    .position(x: slot.bottomCenter.x, y: slot.bottomCenter.y - slot.size.height / 2)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .opacity(isHidden ? 0 : 1)
    }

    static func layout(count: Int, zoom: CGFloat = 1) -> (size: CGSize, slots: [PlaylistPosterSlot]) {
        let unit = PlaylistFolderCover.fanUnit(mainWidth: mainWidth * zoom, count: count)
        let slots = PlaylistFolderCover.fanSlots(count: count, unit: unit, baseline: .zero)
        let bounds = slots.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return (.zero, []) }
        let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
        return (bounds.size, slots.map { $0.offset(by: origin) })
    }
}

#Preview("Веер: 1, 2, 3 постера") {
    PlaylistsPreview { playlists in
        VStack(spacing: 32) {
            if let playlist = playlists.playlists.first {
                ForEach(1...PlaylistFolderCover.posterCount, id: \.self) { count in
                    PlaylistPosterFan(posters: playlist.folderPosters(count: count))
                }
            }
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
