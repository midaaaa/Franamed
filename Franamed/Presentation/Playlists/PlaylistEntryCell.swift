//
//  PlaylistEntryCell.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistEntryCell: View {
    let display: PlaylistEntryDisplay
    let number: Int
    let posterURL: URL?
    var isNew = false

    var body: some View {
        Color.clear
            .aspectRatio(PlaylistStyle.posterAspectRatio, contentMode: .fit)
            .overlay { content }
            .clipShape(PlaylistCellShape(isTorn: isPlayed))
            .overlay(alignment: .topLeading) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(3)
                }
            }
            .overlay(alignment: .bottomTrailing) { marker }
            .overlay {
                if display == .next {
                    RoundedRectangle(cornerRadius: PlaylistStyle.cellCornerRadius)
                        .stroke(.primary, lineWidth: 1.5)
                }
            }
    }

    private var isPlayed: Bool {
        switch display {
        case .guessed, .missed: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch display {
        case .guessed:
            CachedRemoteImage(url: posterURL)
        case .missed:
            CachedRemoteImage(url: posterURL)
                .brightness(-0.12)
        case .next, .upcoming:
            ZStack {
                Rectangle().fill(.fill.tertiary)
                numberLabel
            }
        }
    }

    private var numberLabel: some View {
        Text(number, format: .number.precision(.integerLength(2)))
            .font(.system(.caption, design: .monospaced).weight(display == .next ? .bold : .regular))
            .foregroundStyle(display == .next ? .primary : .secondary)
    }

    @ViewBuilder
    private var marker: some View {
        switch display {
        case .guessed:
            badge("checkmark", color: PlaylistStyle.hit)
        case .missed:
            badge("xmark", color: PlaylistStyle.miss)
        default:
            EmptyView()
        }
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
            .padding(3)
    }
}

struct PlaylistCellShape: Shape {
    let isTorn: Bool

    func path(in rect: CGRect) -> Path {
        let radius = PlaylistStyle.cellCornerRadius
        guard isTorn else {
            return RoundedRectangle(cornerRadius: radius).path(in: rect)
        }
        let teeth = 7
        let depth: CGFloat = 3
        let step = rect.width / CGFloat(teeth)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        for index in 0..<teeth {
            let x = rect.minX + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x + step / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x + step, y: rect.minY + depth))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Ячейки подборки") {
    PlaylistsPreview { playlists in
        if let playlist = playlists.playlists.first {
            LazyVGrid(columns: Array(repeating: GridItem(spacing: PlaylistStyle.gridSpacing), count: PlaylistStyle.gridColumns)) {
                ForEach(Array(playlist.playableItems.enumerated()), id: \.element.key) { index, entry in
                    PlaylistEntryCell(display: playlist.display(of: entry), number: index + 1,
                                      posterURL: entry.posterImageURL)
                }
            }
            .padding()
        }
    }
}
