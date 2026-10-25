//
//  PlaylistLightboxControls.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistLightboxToolbar: ToolbarContent {
    let actions: [FlipMenuItem]
    let areActionsEnabled: Bool
    let onClose: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close, action: onClose)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            ForEach(actions) { action in
                Button(action: action.action) {
                    Label(action.shownTitle, systemImage: action.shownImage)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(!areActionsEnabled)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }
}

struct PlaylistLightboxCloseButton: View {
    let isShown: Bool
    let onClose: () -> Void

    private static let size: CGFloat = 44

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .regular))
                .imageScale(.large)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .modifier(Reveal(isShown: isShown, slide: -Reveal.slide))
    }
}

struct PlaylistLightboxButtons: View {
    let actions: [FlipMenuItem]
    let isShown: Bool
    let width: CGFloat

    private static let size: CGFloat = 56
    private static let iconSize: CGFloat = 20
    private static let placeholder = FlipMenuItem(title: " ", systemImage: "circle", action: {})

    var body: some View {
        ZStack {
            button(Self.placeholder).hidden()
            HStack(alignment: .top) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Spacer(minLength: 0) }
                    button(action)
                }
            }
            .frame(width: width)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .modifier(Reveal(isShown: isShown, slide: Reveal.slide))
    }

    private func button(_ action: FlipMenuItem) -> some View {
        VStack(spacing: 6) {
            Button(action: action.action) {
                Image(systemName: action.shownImage)
                    .font(.system(size: Self.iconSize, weight: .regular))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.size, height: Self.size)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            Text(action.shownTitle)
                .font(.footnote)
                .contentTransition(.identity)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: Self.size)
    }
}

private struct Reveal: ViewModifier {
    let isShown: Bool
    let slide: CGFloat

    static let slide: CGFloat = 24
    private static let animation = Animation.spring(response: 0.34, dampingFraction: 0.82)

    func body(content: Content) -> some View {
        content
            .offset(y: isShown ? 0 : slide)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .animation(Self.animation, value: isShown)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}
