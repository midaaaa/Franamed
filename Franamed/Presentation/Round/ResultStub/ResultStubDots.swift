//
//  ResultStubDots.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

enum ResultStubMark: Hashable {
    case unseen, open, wrong, correct

    static func live(frameCount: Int, attemptsMade: Int, revealedCount: Int, outcome: RoundOutcome?) -> [ResultStubMark] {
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
    let marks: [ResultStubMark]
    var current: Int?

    private static let dotSize: CGFloat = 6
    private static let ringSize: CGFloat = 11

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(marks.indices, id: \.self) { index in
                Circle()
                    .fill(color(for: marks[index]))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .frame(width: slot, height: slot)
                    .overlay {
                        if index == current {
                            Circle()
                                .stroke(.black.opacity(0.7), lineWidth: 1)
                                .frame(width: Self.ringSize, height: Self.ringSize)
                        }
                    }
            }
        }
    }

    private var slot: CGFloat { current == nil ? Self.dotSize : Self.ringSize }

    private var spacing: CGFloat { current == nil ? 5 : 3 }

    private func color(for mark: ResultStubMark) -> Color {
        switch mark {
        case .unseen: .black.opacity(0.18)
        case .open: .black.opacity(0.7)
        case .wrong: .red
        case .correct: .green
        }
    }
}
