//
//  PvPStyle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

enum PvPStyle {
    static let inset: CGFloat = 20
    static let spacing: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let rowHeight: CGFloat = 52
    static let maxWidth: CGFloat = 560

    static let kicker = PlaylistStyle.kicker
    static let title = Font.system(.title2, design: .serif).weight(.bold)
    static let largeTitle = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let score = Font.system(.body, design: .monospaced).weight(.semibold)
    static let code = Font.system(size: 34, weight: .heavy, design: .monospaced)

    static let win = PlaylistStyle.gold
    static let hit = PlaylistStyle.hit
    static let miss = PlaylistStyle.miss

    static func tone(_ tone: PvPPlayerRow.Tone) -> Color {
        switch tone {
        case .ready: hit
        case .waiting: .secondary
        case .away: PlaylistStyle.gold
        case .offline, .left: miss
        }
    }
}

struct PvPKicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PvPStyle.kicker)
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PvPCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PvPStyle.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: shape)
    }
}

struct PvPPrimaryButton: View {
    let title: String
    var isEnabled = true
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(isEnabled ? Accent.action : .gray)
        .foregroundStyle(isEnabled ? Accent.actionForeground : .white)
        .disabled(!isEnabled || isBusy)
        .animation(.snappy, value: isEnabled)
    }
}

struct PvPPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: PvPStyle.spacing) {
                content
            }
            .frame(maxWidth: PvPStyle.maxWidth)
            .padding(.horizontal, PvPStyle.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview("Карточка и кнопки") {
    PvPPage {
        PvPKicker(text: "Комната")
        PvPCard {
            Text("Содержимое карточки")
        }
        PvPPrimaryButton(title: "Готов") {}
        PvPPrimaryButton(title: "Начать", isEnabled: false) {}
        PvPPrimaryButton(title: "Создать", isBusy: true) {}
    }
    .preferredColorScheme(.dark)
}
