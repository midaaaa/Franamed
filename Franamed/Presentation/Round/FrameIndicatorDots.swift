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
    let answeredFrameIndex: Int?
    let outcome: RoundOutcome?
    private let totalFrames = RoundViewModel.maxAttempts

    private enum DotState {
        case unseen, wrong, active, correct
    }

    private func state(for index: Int) -> DotState {
        if let answeredFrameIndex {
            if index == answeredFrameIndex {
                return outcome == .correct ? .correct : .wrong
            }
            
            if outcome == .correct {
                return index < answeredFrameIndex ? .wrong : .unseen
            }
            return index < revealedCount ? .wrong : .unseen
        }

        if index >= revealedCount {
            return .unseen
        }
        if index < revealedCount - 1 {
            return .wrong
        }
        return .active
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
        FrameIndicatorDots(revealedCount: 1, currentFrameIndex: 0, answeredFrameIndex: nil, outcome: nil)

        Text("3 wrong guesses so far, on the 4th").font(.caption)
        FrameIndicatorDots(revealedCount: 4, currentFrameIndex: 3, answeredFrameIndex: nil, outcome: nil)

        Text("Correct on the 3rd attempt (1–2 wrong, 4–6 never attempted)").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 2, answeredFrameIndex: 2, outcome: .correct)

        Text("Wrong on the 6th (final) attempt").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 5, answeredFrameIndex: 5, outcome: .incorrect)

        Text("Wrong on the 6th, submitted while browsing back to frame 3").font(.caption)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 2, answeredFrameIndex: 2, outcome: .incorrect)
    }
    .padding()
}
