//
//  PvPAvatarView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

enum PvPAvatarStyle {
    static func symbol(_ icon: String) -> String {
        switch icon {
        case "popcorn": "popcorn.fill"
        case "clapper": "movieclapper.fill"
        case "camera": "video.fill"
        case "film": "film.fill"
        case "ticket": "ticket.fill"
        case "glasses3d": "eyeglasses"
        case "seat": "chair.lounge.fill"
        case "spotlight": "flashlight.on.fill"
        case "masks": "theatermasks.fill"
        case "megaphone": "megaphone.fill"
        case "star": "star.fill"
        case "projector": "videoprojector.fill"
        default: "person.fill"
        }
    }

    static func color(_ color: String) -> Color {
        switch color {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        default: .gray
        }
    }
}

struct PvPAvatarView: View {
    let avatar: PvPAvatar
    var size: CGFloat = 36
    var isDimmed = false

    var body: some View {
        Image(systemName: PvPAvatarStyle.symbol(avatar.icon))
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PvPAvatarStyle.color(avatar.color).gradient, in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            .saturation(isDimmed ? 0 : 1)
            .opacity(isDimmed ? 0.5 : 1)
    }
}

#Preview("Все иконки") {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
        ForEach(Array(PvPProfileRules.icons.enumerated()), id: \.offset) { index, icon in
            PvPAvatarView(avatar: PvPAvatar(icon: icon, color: PvPProfileRules.colors[index % PvPProfileRules.colors.count]), size: 52)
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Размеры и приглушение") {
    HStack(spacing: 16) {
        PvPAvatarView(avatar: PvPAvatar(icon: "popcorn", color: "red"), size: 24)
        PvPAvatarView(avatar: PvPAvatar(icon: "clapper", color: "blue"))
        PvPAvatarView(avatar: PvPAvatar(icon: "masks", color: "purple"), size: 64)
        PvPAvatarView(avatar: PvPAvatar(icon: "projector", color: "mint"), isDimmed: true)
    }
    .padding()
    .preferredColorScheme(.dark)
}
