//
//  PlaylistStyle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

enum PlaylistStyle {
    static let hit = Color(red: 0.37, green: 0.75, blue: 0.53)
    static let miss = Color(red: 0.88, green: 0.39, blue: 0.30)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let goldOnPaper = Color(red: 1.0, green: 0.72, blue: 0.0)
    static let trackOnPaper = Color.black.opacity(0.18)

    static func title(zoom: CGFloat) -> Font {
        scaledFont(.title2, zoom: zoom, weight: .bold, design: .serif)
    }

    static func scaledFont(_ style: UIFont.TextStyle, zoom: CGFloat, weight: Font.Weight,
                           design: Font.Design) -> Font {
        .system(size: UIFont.preferredFont(forTextStyle: style).pointSize * zoom, weight: weight, design: design)
    }
    static let shelfTitle = Font.system(.headline, design: .serif)
    static let description = Font.system(.body, design: .serif)
    static let kicker = Font.system(.caption2, design: .monospaced).weight(.semibold)

    static let shelfMaxColumns = 4
    static let shelfMinFolderWidth: CGFloat = 150
    static let shelfInset: CGFloat = 20
    static let shelfSpacingRange: ClosedRange<CGFloat> = 16...32
    static let shelfSpacingShare: CGFloat = 0.045
    static let gridColumns = 5
    static let gridMaxColumns = 6
    static let gridMinPosterWidth: CGFloat = 64
    static let gridInset: CGFloat = 20
    static let gridSpacing: CGFloat = 8
    static let pageReferenceWidth: CGFloat = 393
    static let pageMaxZoom: CGFloat = 1.6

    static func pageZoom(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(width / pageReferenceWidth, pageMaxZoom)
    }

    static func pageInset(forWidth width: CGFloat) -> CGFloat {
        gridInset * pageZoom(forWidth: width)
    }

    static func gridColumns(width: CGFloat) -> Int {
        guard width > 0 else { return gridColumns }
        let minPosterWidth = gridMinPosterWidth * pageZoom(forWidth: width)
        let fitting = Int((width - pageInset(forWidth: width) * 2 + gridSpacing) / (minPosterWidth + gridSpacing))
        return min(max(fitting, gridColumns), gridMaxColumns)
    }

    static func shelfLayout(width: CGFloat) -> (columns: Int, spacing: CGFloat) {
        guard width > 0 else { return (2, shelfSpacingRange.lowerBound) }
        let content = max(0, width - shelfInset * 2)
        let spacing = min(max(content * shelfSpacingShare, shelfSpacingRange.lowerBound), shelfSpacingRange.upperBound)
        let fitting = Int((content + spacing) / (shelfMinFolderWidth + spacing))
        return (min(max(fitting, 1), shelfMaxColumns), spacing)
    }
}

struct PlaylistSealStamp: View, Animatable {
    var isGold = false
    var progress: Double = 1

    private static let size: CGFloat = 34
    private static let bleed: CGFloat = 4

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let size = Self.size
        let radius = size / 2
        let fold = -radius + CGFloat(min(max(progress, 0), 1)) * size
        let laid = min(max(fold + radius, 0), size)
        let lifted = size - laid
        let bleed = Self.bleed
        let full = size + bleed * 2
        ZStack {
            face
                .padding(bleed)
                .rotationEffect(.degrees(-45))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: laid == 0 ? 0 : laid + bleed + (lifted == 0 ? bleed : 0))
                }
            backing
                .padding(bleed)
                .rotationEffect(.degrees(-45))
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: lifted == 0 ? 0 : lifted + bleed + (laid == 0 ? bleed : 0))
                }
                .scaleEffect(x: -1, y: 1, anchor: UnitPoint(x: (laid + bleed) / full, y: 0.5))
                .shadow(color: .black.opacity(0.35 * min(1, lifted / radius)), radius: 2, x: 1.5, y: 1.5)
        }
        .frame(width: full, height: full)
        .rotationEffect(.degrees(45))
        .padding(-bleed)
        .opacity(min(1, progress * 5))
    }

    private var face: some View {
        Image(systemName: "checkmark.seal")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: Self.size, height: Self.size)
            .background(isGold ? PlaylistStyle.gold : .white, in: Circle())
            .overlay(Circle().stroke(.black, lineWidth: 1.5))
            .overlay(Circle().inset(by: 3.5).stroke(.black.opacity(0.6), lineWidth: 0.75))
    }

    private var backing: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.78)],
                                 startPoint: .trailing, endPoint: .leading))
            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
            .frame(width: Self.size, height: Self.size)
    }
}
