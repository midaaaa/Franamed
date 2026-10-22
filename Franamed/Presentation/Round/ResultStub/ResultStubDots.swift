//
//  ResultStubDots.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

enum ResultStubMark: Hashable {
    case unseen, open, wrong, correct
}

struct ResultStubProgress: Hashable {
    let frameCount: Int
    let attemptsMade: Int
    let revealedCount: Int
    let outcome: RoundOutcome?
    let currentFrame: Int?

    static func finished(frameCount: Int, attemptsMade: Int, outcome: RoundOutcome) -> ResultStubProgress {
        ResultStubProgress(frameCount: frameCount, attemptsMade: attemptsMade, revealedCount: frameCount,
                           outcome: outcome, currentFrame: nil)
    }

    static func unplayed(frameCount: Int) -> ResultStubProgress {
        ResultStubProgress(frameCount: frameCount, attemptsMade: 0, revealedCount: 0, outcome: nil, currentFrame: nil)
    }

    func withoutCursor() -> ResultStubProgress {
        ResultStubProgress(frameCount: frameCount, attemptsMade: attemptsMade, revealedCount: revealedCount,
                           outcome: outcome, currentFrame: nil)
    }

    var marks: [ResultStubMark] {
        let misses = outcome == .correct ? attemptsMade - 1 : attemptsMade
        return (0..<frameCount).map { index in
            if index < misses { return .wrong }
            if outcome == .correct, index == misses { return .correct }
            if outcome == nil, index == revealedCount - 1 { return .open }
            return .unseen
        }
    }
}

struct ResultStubDots: View {
    let progress: ResultStubProgress
    var reservesRing = true

    private static let dotSize: CGFloat = 6
    private static let ringSize: CGFloat = 11
    private static let spacing: CGFloat = 3
    private static let compactSpacing: CGFloat = 5

    var body: some View {
        let marks = progress.marks
        return HStack(spacing: reservesRing ? Self.spacing : Self.compactSpacing) {
            ForEach(marks.indices, id: \.self) { index in
                Circle()
                    .fill(color(for: marks[index]))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .frame(width: slot, height: slot)
                    .overlay {
                        if index == progress.currentFrame {
                            Circle()
                                .stroke(.black.opacity(0.7), lineWidth: 1)
                                .frame(width: Self.ringSize, height: Self.ringSize)
                        }
                    }
            }
        }
    }

    private var slot: CGFloat { reservesRing ? Self.ringSize : Self.dotSize }

    private func color(for mark: ResultStubMark) -> Color {
        switch mark {
        case .unseen: .black.opacity(0.18)
        case .open: .black.opacity(0.7)
        case .wrong: .red
        case .correct: .green
        }
    }
}
