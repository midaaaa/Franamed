//
//  PlaylistFolderCover.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.10.2026.
//

import SwiftUI

struct PlaylistPosterSlot {
    var bottomCenter: CGPoint
    var size: CGSize
    var angle: Double

    func offset(by origin: CGPoint) -> PlaylistPosterSlot {
        var slot = self
        slot.bottomCenter.x += origin.x
        slot.bottomCenter.y += origin.y
        return slot
    }

    var boundingBox: CGRect {
        CGRect(x: -size.width / 2, y: -size.height, width: size.width, height: size.height)
            .applying(CGAffineTransform(rotationAngle: angle * .pi / 180))
            .offsetBy(dx: bottomCenter.x, dy: bottomCenter.y)
    }
}

struct PlaylistFolderContent {
    let posters: [URL?]
    let seed: String
    var mediaType = MediaType.movie
    var total = 0
    var answered = 0
    var correct = 0
    var completion = PlaylistCompletion.inProgress
}

extension PlaylistDetail {
    var folderContent: PlaylistFolderContent {
        PlaylistFolderContent(posters: folderPosters(count: PlaylistFolderCover.posterCount), seed: id,
                              mediaType: mediaType, total: availableCount, answered: answeredCount,
                              correct: correctCount, completion: completion)
    }
}

struct PlaylistFolderCover: View {
    let content: PlaylistFolderContent
    var addedCount = 0
    var isOpen = false
    var isSelected = false
    var posterOverride: [PlaylistPosterSlot]?
    var hidesPosters = false

    static let posterCornerRadius: CGFloat = 4
    nonisolated static let posterCount = 3

    private enum Metrics {
        static let aspectRatio: CGFloat = 1.15
        static let backWidth: CGFloat = 0.9
        static let backHeight: CGFloat = 0.72
        static let backBottom: CGFloat = 0.03
        static let backRadius: CGFloat = 12
        static let posterBackHeight: CGFloat = 0.84
        static let frontHeight: CGFloat = 0.49
        static let openFront: CGFloat = 0.8
        static let taper: CGFloat = (1 - backWidth) / 2
        static let posterWidth: CGFloat = 0.3
        static let posterOffset: CGFloat = -0.07
        static let liftScale: CGFloat = 2
        static let backTint: Double = 0.2
        static let backUnderlay: Double = 0.15
        static let frontTint: Double = 0.35
        static let frontUnderlay: Double = 0.22
    }

    private var completion: PlaylistCompletion { content.completion }
    private var tint: Color? { completion == .perfect ? PlaylistStyle.gold : nil }

    var body: some View {
        Color.clear
            .aspectRatio(Metrics.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    folder(in: geo.size)
                }
            }
    }

    // MARK: Layers

    private func folder(in size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            back(in: size)
            posterStack(in: size)
            front(width: size.width, height: size.height * Metrics.frontHeight)
                .scaleEffect(x: 1, y: isOpen ? Metrics.openFront : 1, anchor: .bottom)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isOpen)
        }
        .frame(width: size.width, height: size.height)
    }

    private func back(in size: CGSize) -> some View {
        let shape = PlaylistFolderBackShape(radius: Metrics.backRadius)
        return Color.clear
            .background { if let tint { shape.fill(tint.opacity(Metrics.backUnderlay)) } }
            .glassEffect(.regular.tint(tint?.opacity(Metrics.backTint)), in: shape)
            .frame(width: size.width * Metrics.backWidth, height: size.height * Metrics.backHeight)
            .padding(.bottom, size.height * Metrics.backBottom)
    }

    private func posterStack(in size: CGSize) -> some View {
        let posters = Array(content.posters.prefix(Self.posterCount))
        let slots = posterOverride ?? Self.posterSlots(count: posters.count, in: size, isOpen: isOpen)
        return ZStack {
            ForEach(Array(zip(posters, slots).enumerated()).reversed(), id: \.offset) { _, pair in
                let (poster, slot) = pair
                CachedRemoteImage(url: poster)
                    .frame(width: slot.size.width, height: slot.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Self.posterCornerRadius))
                    .rotationEffect(.degrees(slot.angle), anchor: .bottom)
                    .position(x: slot.bottomCenter.x, y: slot.bottomCenter.y - slot.size.height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(hidesPosters ? 0 : 1)
        .animation(posterOverride == nil ? .spring(response: 0.35, dampingFraction: 0.62) : nil, value: isOpen)
    }

    private func front(width: CGFloat, height: CGFloat) -> some View {
        let shape = PlaylistFolderFrontShape(taper: Metrics.taper)
        let inset = width * Metrics.taper
        return Color.clear
            .background { if let tint { shape.fill(tint.opacity(Metrics.frontUnderlay)) } }
            .glassEffect(.regular.tint(tint?.opacity(Metrics.frontTint)), in: shape)
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if content.total > 0 {
                    PlaylistFolderSticker(content: content, angle: stickerAngle)
                        .padding(.trailing, inset * (1 - 14 / max(height, 1)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected { selectionMark }
            }
            .overlay(alignment: .topLeading) {
                if addedCount > 0 {
                    PlaylistNewBadge(count: addedCount)
                        .padding(.leading, 8 + inset * 17 / max(height, 1))
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if completion != .inProgress {
                    PlaylistSealStamp(isGold: completion == .perfect)
                        .shadow(color: PlaylistStyle.gold.opacity(completion == .perfect ? 0.5 : 0), radius: 6)
                        .rotationEffect(.degrees(stampAngle))
                        .scaleEffect(0.85, anchor: .bottomLeading)
                        .padding(.leading, 10 + inset * (1 - 20 / max(height, 1)))
                        .padding(.bottom, 8)
                }
            }
    }

    private var selectionMark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(.white, in: Circle())
            .padding(.trailing, 9)
            .padding(.top, 9)
    }

    private var stampAngle: Double {
        let a = PlaylistSeed.unit(content.seed)
        return a < 0.7 ? -(4 + a / 0.7 * 5) : 4 + (a - 0.7) / 0.3 * 5
    }

    private var stickerAngle: Double {
        let a = PlaylistSeed.unit(content.seed + "sticker")
        return a < 0.5 ? -(2 + a / 0.5 * 3) : 2 + (a - 0.5) / 0.5 * 3
    }

    // MARK: Geometry

    static func posterSlots(count: Int, in size: CGSize, isOpen: Bool) -> [PlaylistPosterSlot] {
        let count = min(count, posterCount)
        let backHeight = size.height * Metrics.posterBackHeight
        let backTop = size.height * (1 - Metrics.backBottom) - backHeight
        let bottom = backTop + PlaylistFolderBackShape.tabHeight(in: backHeight) + 2 + size.width * Metrics.posterWidth * 1.5
        let baseline = CGPoint(x: size.width / 2, y: bottom - size.width * Metrics.posterOffset)
        let fan = fanSlots(count: count, unit: size.width, baseline: baseline)
        guard isOpen else { return fan }
        return zip(fan, fanSpecs(count: count)).map { slot, spec in
            let lift = min(size.width * spec.lift * Metrics.liftScale, max(0, slot.bottomCenter.y - slot.size.height - 2))
            var lifted = slot
            lifted.bottomCenter.y -= lift
            return lifted
        }
    }

    static func fanSlots(count: Int, unit: CGFloat, baseline: CGPoint) -> [PlaylistPosterSlot] {
        let width = unit * Metrics.posterWidth * posterScale(count: count)
        return fanSpecs(count: count).map { spec in
            PlaylistPosterSlot(bottomCenter: CGPoint(x: baseline.x + unit * spec.x, y: baseline.y + unit * spec.drop),
                               size: CGSize(width: width, height: width * 1.5),
                               angle: spec.angle)
        }
    }

    static func fanUnit(mainWidth: CGFloat, count: Int) -> CGFloat {
        mainWidth / (Metrics.posterWidth * posterScale(count: min(count, posterCount)))
    }

    static func frontTop(in size: CGSize, isOpen: Bool = false) -> CGFloat {
        size.height * (1 - Metrics.frontHeight * (isOpen ? Metrics.openFront : 1))
    }

    static func restTop(width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: width / Metrics.aspectRatio)
        let backTop = size.height * (1 - Metrics.backBottom - Metrics.backHeight)
        let posterTop = (1...posterCount).flatMap { posterSlots(count: $0, in: size, isOpen: false) }
            .map(\.boundingBox.minY).min() ?? backTop
        return min(backTop, posterTop)
    }

    private static func fanSpecs(count: Int) -> [(x: CGFloat, angle: Double, drop: CGFloat, lift: CGFloat)] {
        switch count {
        case 0: []
        case 1: [(0, 0, 0, 0.1)]
        case 2: [(-0.12, -6, 0.01, 0.1), (0.12, 6, 0.01, 0.095)]
        default: [(0, 0, 0, 0.1), (-0.2, -8, 0.03, 0.085), (0.2, 8, 0.03, 0.085)]
        }
    }

    private static func posterScale(count: Int) -> CGFloat {
        switch count {
        case 1: 1.15
        case 2: 1.12
        default: 1
        }
    }
}

// MARK: - Parts

private struct PlaylistFolderSticker: View {
    let content: PlaylistFolderContent
    let angle: Double

    private static let correctInk = Color(red: 0.24, green: 0.48, blue: 0.32)

    var body: some View {
        label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.13))
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .padding(.vertical, 4)
            .background(Color(red: 0.94, green: 0.9, blue: 0.82), in: PlaylistStickerShape())
            .rotationEffect(.degrees(angle))
            .padding(.trailing, 10)
            .padding(.bottom, 9)
    }

    @ViewBuilder
    private var label: some View {
        if content.answered == 0 || content.completion == .perfect {
            Text(RussianPlural.titles(content.total, mediaType: content.mediaType))
        } else if content.completion == .passed {
            Text("\(Text("\(content.correct)").foregroundStyle(Self.correctInk))/\(content.total)")
        } else {
            Text("\(content.answered)/\(content.total)")
        }
    }
}

private struct PlaylistStickerShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 2)
            .subtracting(Path(ellipseIn: CGRect(x: rect.minX - 4, y: rect.midY - 4, width: 8, height: 8)))
    }
}

private struct PlaylistNewBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Accent.reward, in: Capsule())
            .foregroundStyle(.black)
    }
}

private struct PlaylistFolderBackShape: Shape {
    var radius: CGFloat = 12

    static func tabHeight(in height: CGFloat) -> CGFloat {
        min(14, height * 0.08)
    }

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + Self.tabHeight(in: rect.height)
        let tabWidth = rect.width * 0.42
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tabWidth - 8, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX + tabWidth + 8, y: top),
                      control1: CGPoint(x: rect.minX + tabWidth, y: rect.minY),
                      control2: CGPoint(x: rect.minX + tabWidth, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PlaylistFolderFrontShape: Shape {
    var taper: CGFloat = 0
    var radius: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * taper
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Папки: все с сервера, нажата, выбрана, новые") {
    PlaylistsPreview { playlists in
        ScrollView {
            LazyVGrid(columns: [GridItem(), GridItem()], spacing: 16) {
                ForEach(playlists.playlists) { playlist in
                    PlaylistFolderCover(content: playlist.folderContent)
                }
                if let playlist = playlists.playlists.first {
                    PlaylistFolderCover(content: playlist.folderContent, isOpen: true)
                    PlaylistFolderCover(content: playlist.folderContent, isSelected: true)
                    PlaylistFolderCover(content: playlist.folderContent, addedCount: 2)
                }
            }
            .padding(16)
        }
        .background(Color(white: 0.08))
        .preferredColorScheme(.dark)
    }
}
