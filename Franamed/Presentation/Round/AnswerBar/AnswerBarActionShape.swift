//
//  AnswerBarActionShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.08.2026.
//

import SwiftUI

struct AnswerBarActionShape: View, Animatable {
    var progress: Double
    let width: CGFloat
    var isBlocked: Bool
    let onSubmit: () -> Void
    let onNewGame: () -> Void

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private let collapsedSide: CGFloat = 32
    private let trailingInset: CGFloat = 6

    private let arrowFadeEnd = 0.4
    private let textFadeStart = 0.2
    private let textFadeEnd = 0.4

    private var arrowOpacity: Double {
        max(0, 1 - progress / arrowFadeEnd)
    }

    private var textOpacity: Double {
        guard progress > textFadeStart else { return 0 }
        guard progress < textFadeEnd else { return 1 }
        return (progress - textFadeStart) / (textFadeEnd - textFadeStart)
    }

    var body: some View {
        let barHeight = suggestionRowHeight
        let shapeWidth = collapsedSide + (width - collapsedSide) * progress
        let shapeHeight = collapsedSide + (barHeight - collapsedSide) * progress
        let cornerRadius = shapeHeight / 2
        let collapsedCenterX = width - trailingInset - collapsedSide / 2
        let expandedCenterX = width / 2
        let shapeCenterX = collapsedCenterX + (expandedCenterX - collapsedCenterX) * progress

        let glassShape: AnyShape = progress < 0.02
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius))

        let isAtRest = progress == 0 || progress == 1
        let glassStyle = isAtRest
            ? Glass.regular.tint(isBlocked ? .gray : .accentColor).interactive()
            : Glass.regular.tint(isBlocked ? .gray : .accentColor)

        Button(action: progress < 0.5 ? onSubmit : onNewGame) {
            ZStack {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .opacity(arrowOpacity)
                Text("New game")
                    .font(.headline)
                    .opacity(textOpacity)
            }
            .foregroundStyle(.white)
            .frame(width: shapeWidth, height: shapeHeight)
            .contentShape(glassShape)
        }
        .buttonStyle(.plain)
        .glassEffect(glassStyle, in: glassShape)
        .animation(.snappy, value: isBlocked)
        .allowsHitTesting(isAtRest)
        .position(x: shapeCenterX, y: barHeight / 2)
    }
}

#Preview {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("Blocked (loading)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: true, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("Mid-morph (progress 0.5)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0.5, width: proxy.size.width, isBlocked: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("New Game (progress 1)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 1, width: proxy.size.width, isBlocked: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}
