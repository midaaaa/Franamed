//
//  RoundComponents.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameView: View {
    let backdrops: [Backdrop]
    let currentFrameIndex: Int
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let backdrop = backdrops[safe: currentFrameIndex],
                   let url = URL(string: backdrop.filePath) {
                    CachedAsyncImage(url: url)
                }
            }
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onTapPrevious() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onTapNext() }
                }
            }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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
            return index < answeredFrameIndex ? .wrong : .unseen
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

struct ResultBanner: View {
    let outcome: RoundOutcome
    let movieTitle: String

    var body: some View {
        VStack(spacing: 8) {
            Label(
                outcome == .correct ? "Correct" : "Incorrect",
                systemImage: outcome == .correct ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(outcome == .correct ? .green : .red)

            Text(movieTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

#Preview("Frame") {
    FrameView(
        backdrops: (1...6).map { Backdrop(filePath: "https://picsum.photos/seed/backdrop\($0)/1280/720") },
        currentFrameIndex: 0,
        onTapPrevious: {},
        onTapNext: {}
    )
}

#Preview("Frame — loading") {
    FrameView(backdrops: [], currentFrameIndex: 0, onTapPrevious: {}, onTapNext: {})
}

#Preview("Indicator dots") {
    VStack(spacing: 20) {
        FrameIndicatorDots(revealedCount: 1, currentFrameIndex: 0, answeredFrameIndex: nil, outcome: nil)
        FrameIndicatorDots(revealedCount: 4, currentFrameIndex: 3, answeredFrameIndex: nil, outcome: nil)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 2, answeredFrameIndex: 2, outcome: .correct)
        FrameIndicatorDots(revealedCount: 6, currentFrameIndex: 5, answeredFrameIndex: 5, outcome: .incorrect)
    }
    .padding()
}

#Preview("Result banner") {
    VStack(spacing: 24) {
        ResultBanner(outcome: .correct, movieTitle: "Everything Everywhere All at Once")
        ResultBanner(outcome: .incorrect, movieTitle: "Up")
    }
}
