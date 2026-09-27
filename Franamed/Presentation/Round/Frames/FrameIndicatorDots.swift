//
//  FrameIndicatorDots.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameIndicatorDots: View {
    let revealedCount: Int
    let currentFrameIndex: Int
    let attemptsMade: Int
    let outcome: RoundOutcome?
    let totalFrames: Int

    private enum DotState {
        case unseen, wrong, active, correct
    }

    private func state(for index: Int) -> DotState {
        let misses = outcome == .correct ? attemptsMade - 1 : attemptsMade
        if index < misses { return .wrong }
        if outcome == .correct, index == misses { return .correct }
        if outcome == nil, index == revealedCount - 1 { return .active }
        return .unseen
    }

    private func color(for state: DotState) -> Color {
        switch state {
        case .unseen: .gray.opacity(0.3)
        case .wrong: .red
        case .active: .primary
        case .correct: .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalFrames, id: \.self) { index in
                Circle()
                    .fill(color(for: state(for: index)))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if index == currentFrameIndex {
                            Circle()
                                .stroke(Color.primary, lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                        }
                    }
            }
        }
    }
}

#Preview("Indicator dots") {
    VStack(alignment: .leading, spacing: 20) {
        Text("First attempt").font(.caption)
        FrameIndicatorDots(revealedCount: 1, currentFrameIndex: 0, attemptsMade: 0, outcome: nil, totalFrames: 6)

        Text("3 wrong guesses so far, browsing back to frame 2").font(.caption)
        FrameIndicatorDots(revealedCount: 4, currentFrameIndex: 1, attemptsMade: 3, outcome: nil, totalFrames: 6)

        Text("Correct on the 4th attempt while browsing frame 2").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 1, attemptsMade: 4, outcome: .correct, totalFrames: 6)

        Text("Correct on the 1st attempt").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 0, attemptsMade: 1, outcome: .correct, totalFrames: 6)

        Text("Wrong on the 6th, browsing back to frame 3").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 2, attemptsMade: 6, outcome: .incorrect, totalFrames: 6)
    }
    .padding()
}
