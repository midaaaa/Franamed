//
//  PlaylistLightboxControls.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistLightboxControls: View {
    let showsClose: Bool
    let showsActions: Bool
    let actions: [FlipMenuItem]
    let onClose: () -> Void

    private static let closeSize: CGFloat = 44
    private static let actionSize: CGFloat = 56
    private static let actionIconSize: CGFloat = 20
    private static let slide: CGFloat = 24
    private static let animation = Animation.spring(response: 0.34, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
            }
            .padding(.horizontal, 16)
            .modifier(Reveal(isShown: showsClose, slide: -Self.slide))
            Spacer()
            HStack(alignment: .top) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Spacer() }
                    actionButton(action)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .modifier(Reveal(isShown: showsActions, slide: Self.slide))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .regular))
                .imageScale(.large)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Закрыть")
    }

    private func actionButton(_ action: FlipMenuItem) -> some View {
        VStack(spacing: 6) {
            Button(action: action.action) {
                Image(systemName: action.systemImage)
                    .font(.system(size: Self.actionIconSize, weight: .regular))
                    .frame(width: Self.actionSize, height: Self.actionSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(action.title)
            Text(action.title)
                .font(.footnote)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private struct Reveal: ViewModifier {
        let isShown: Bool
        let slide: CGFloat

        func body(content: Content) -> some View {
            content
                .offset(y: isShown ? 0 : slide)
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
                .animation(PlaylistLightboxControls.animation, value: isShown)
        }
    }
}
