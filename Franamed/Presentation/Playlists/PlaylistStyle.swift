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

    static let posterAspectRatio: CGFloat = 2.0 / 3.0
    static let cellCornerRadius: CGFloat = 6

    static let title = Font.system(.title2, design: .serif).weight(.bold)
    static let shelfTitle = Font.system(.headline, design: .serif)
    static let description = Font.system(.body, design: .serif)
    static let meta = Font.system(.caption, design: .monospaced)
    static let kicker = Font.system(.caption2, design: .monospaced).weight(.semibold)

    static let shelfColumns = 2
    static let gridColumns = 5
    static let shelfSpacing: CGFloat = 16
    static let gridSpacing: CGFloat = 8
}

struct PlaylistSealStamp: View {
    var isGold = false

    private var ink: Color { isGold ? .black : Accent.reward }

    var body: some View {
        Image(systemName: "checkmark.seal")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(ink)
            .frame(width: 34, height: 34)
            .background(isGold ? PlaylistStyle.gold : .black.opacity(0.5), in: Circle())
            .overlay(Circle().stroke(ink, lineWidth: 1.5))
            .overlay(Circle().inset(by: 3.5).stroke(ink.opacity(0.6), lineWidth: 0.75))
    }
}
