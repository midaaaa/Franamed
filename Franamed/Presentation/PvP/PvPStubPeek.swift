//
//  PvPStubPeek.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPStubPeek: View {
    let screen: PvPMatchScreen
    let mediaType: MediaType
    let viewedFrame: Int?
    let isRaised: Bool
    let isTucked: Bool
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let lowPeek: CGFloat = 36
    static let highPeek: CGFloat = 74
    private static let inset: CGFloat = 14
    private static let rowGap: CGFloat = 10

    private var ink: TicketInk { .stub(for: mediaType) }

    private var peek: CGFloat { isTucked ? 0 : isRaised ? Self.highPeek : Self.lowPeek }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            HStack(spacing: 12) {
                timer
                Spacer(minLength: 0)
                PvPStubPips(marks: marks, viewed: viewedFrame, ink: ink.ink)
            }
            .frame(height: Self.lowPeek - Self.inset)
            details
                .opacity(isRaised ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, Self.inset - 2)
        .foregroundStyle(ink.ink)
        .frame(width: width, height: Self.highPeek + suggestionRowHeight, alignment: .top)
        .background(ink.paper, in: ResultStubShape(edgeStyle: .straight))
        .offset(y: Self.highPeek - peek)
        .frame(height: Self.highPeek + suggestionRowHeight, alignment: .top)
        .clipped()
        .animation(reduceMotion ? nil : ResultStubPeek.tuckAnimation, value: peek)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var timer: some View {
        if let timer = screen.timer {
            HStack(spacing: 5) {
                if timer.isFrozen {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(timer.text)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            }
            .foregroundStyle(timer.isUrgent ? PvPStubPips.missInk : ink.ink)
            .opacity(timer.isFrozen ? 0.45 : 1)
            .animation(reduceMotion ? nil : .snappy, value: timer.text)
        }
    }

    private var details: some View {
        HStack(spacing: 10) {
            Text(screen.title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .opacity(0.75)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let duel = screen.duel {
                if let multiplier = duel.multiplier {
                    Text(multiplier)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                PvPStubLives(fraction: duel.you.fraction, ink: ink.ink)
            }
        }
    }

    private var marks: [PvPStubPips.Mark] {
        let count = screen.frames.count
        guard let shown = screen.shownFrame else { return Array(repeating: .locked, count: count) }
        let tone = screen.status?.tone
        return (0..<count).map { index in
            if index < shown { return .miss }
            guard index == shown else { return .locked }
            switch tone {
            case .solved: return .hit
            case .failed: return .miss
            default: return .current
            }
        }
    }
}

struct PvPStubPips: View {
    enum Mark { case locked, current, miss, hit }

    let marks: [Mark]
    let viewed: Int?
    let ink: Color

    static let missInk = Color(red: 0.8, green: 0.2, blue: 0.16)
    static let hitInk = Color(red: 0.16, green: 0.58, blue: 0.32)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(mark))
                    .frame(width: 14, height: index == viewed ? 8 : 5)
            }
        }
        .animation(.snappy, value: viewed)
    }

    private func color(_ mark: Mark) -> Color {
        switch mark {
        case .locked: ink.opacity(0.15)
        case .current: ink
        case .miss: Self.missInk
        case .hit: Self.hitInk
        }
    }
}

struct PvPStubLives: View {
    let fraction: Double
    let ink: Color

    private static let width: CGFloat = 80

    private var color: Color {
        switch fraction {
        case ..<0.25: PvPStubPips.missInk
        case ..<0.5: Color(red: 0.85, green: 0.55, blue: 0.1)
        default: PvPStubPips.hitInk
        }
    }

    var body: some View {
        Capsule()
            .fill(ink.opacity(0.12))
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: Self.width * fraction)
            }
            .frame(width: Self.width, height: 6)
            .animation(.snappy, value: fraction)
    }
}

#if DEBUG
#Preview("Корешок матча") {
    VStack(spacing: 60) {
        if let room = PvPPreview.match(PvPMatchFixtures.playingDeadline) {
            PvPStubPeek(screen: room, mediaType: .movie, viewedFrame: nil, isRaised: false, isTucked: false, width: 340)
            PvPStubPeek(screen: room, mediaType: .movie, viewedFrame: 1, isRaised: true, isTucked: false, width: 340)
        }
        if let duel = PvPPreview.match(PvPMatchFixtures.duelPlaying) {
            PvPStubPeek(screen: duel, mediaType: .tv, viewedFrame: nil, isRaised: true, isTucked: false, width: 340)
        }
    }
    .padding(.top, 120)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
#endif
