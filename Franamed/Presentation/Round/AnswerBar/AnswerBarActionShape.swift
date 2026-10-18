//
//  AnswerBarActionShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.08.2026.
//

import SwiftUI

struct AnswerBarNext: Equatable {
    var title: String
    var badge: String?
    var stamp: PlaylistFinish?
}

struct AnswerBarActionShape: View, Animatable {
    var progress: Double
    let width: CGFloat
    var isBlocked: Bool
    let isTransitioning: Bool
    var next = AnswerBarNext(title: "Дальше")
    let onSubmit: () -> Void
    let onNewGame: () -> Void

    static let stampMorphAnimation = Animation.easeInOut(duration: 1.3)

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private let collapsedSide: CGFloat = 32
    private let stampSide: CGFloat = 44
    private let trailingInset: CGFloat = 6

    private let arrowFadeEnd = 0.4
    private let textFadeStart = 0.2
    private let textFadeEnd = 0.4

    private let stampGrowEnd = 0.25
    private let stampHoldEnd = 0.6

    private var morphsViaStamp: Bool { next.stamp != nil }

    private var expansion: Double {
        guard morphsViaStamp else { return progress }
        return max(0, (progress - stampHoldEnd) / (1 - stampHoldEnd))
    }

    private var stampGrowth: Double {
        morphsViaStamp ? min(1, progress / stampGrowEnd) : 0
    }

    private var stampOpacity: Double {
        guard morphsViaStamp else { return 0 }
        return min(stampGrowth, max(0, 1 - expansion / 0.3))
    }

    private var isStampPhase: Bool { morphsViaStamp && progress > 0 && expansion < 0.15 }

    private var arrowOpacity: Double {
        let fade = morphsViaStamp ? stampGrowEnd : arrowFadeEnd
        return max(0, 1 - progress / fade)
    }

    private var textOpacity: Double {
        guard expansion > textFadeStart else { return 0 }
        guard expansion < textFadeEnd else { return 1 }
        return (expansion - textFadeStart) / (textFadeEnd - textFadeStart)
    }

    private var tint: Color {
        if isBlocked { return .gray }
        guard isStampPhase else { return Accent.action }
        return next.stamp == .perfect ? PlaylistStyle.gold : Accent.action
    }

    private var foreground: Color {
        isBlocked ? .white : Accent.actionForeground
    }

    var body: some View {
        let barHeight = suggestionRowHeight
        let startSide = collapsedSide + (stampSide - collapsedSide) * stampGrowth
        let shapeWidth = startSide + (width - startSide) * expansion
        let shapeHeight = startSide + (barHeight - startSide) * expansion
        let cornerRadius = shapeHeight / 2
        let collapsedCenterX = width - trailingInset - collapsedSide / 2
        let expandedCenterX = width / 2
        let shapeCenterX = collapsedCenterX + (expandedCenterX - collapsedCenterX) * expansion

        let glassShape = RoundedRectangle(cornerRadius: cornerRadius)
        let glassStyle = Glass.regular.tint(tint).interactive()

        Button(action: progress < 0.5 ? onSubmit : onNewGame) {
            ZStack {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .opacity(arrowOpacity)
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.black)
                    .scaleEffect(0.6 + 0.4 * stampGrowth)
                    .opacity(stampOpacity)
                HStack(spacing: 8) {
                    Text(next.title)
                        .font(.headline)
                    if let badge = next.badge {
                        Text(badge)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black))
                    }
                }
                .fixedSize()
                .opacity(textOpacity)
            }
            .foregroundStyle(foreground)
            .frame(width: shapeWidth, height: shapeHeight)
            .clipShape(glassShape)
            .contentShape(glassShape)
        }
        .buttonStyle(.plain)
        .glassEffect(glassStyle, in: glassShape)
        .animation(.easeInOut(duration: 0.3), value: isStampPhase)
        .animation(.snappy, value: isBlocked)
        .allowsHitTesting(!isTransitioning)
        .position(x: shapeCenterX, y: barHeight / 2)
    }
}

#Preview {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: false, isTransitioning: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("Blocked (loading)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: true, isTransitioning: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("Mid-morph (progress 0.5)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 0.5, width: proxy.size.width, isBlocked: false, isTransitioning: true, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}

#Preview("New Game (progress 1)") {
    GeometryReader { proxy in
        AnswerBarActionShape(progress: 1, width: proxy.size.width, isBlocked: false, isTransitioning: false, onSubmit: {}, onNewGame: {})
    }
    .frame(height: suggestionRowHeight)
    .padding()
}
