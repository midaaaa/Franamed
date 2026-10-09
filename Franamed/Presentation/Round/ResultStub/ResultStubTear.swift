//
//  ResultStubTear.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 09.10.2026.
//

import Foundation

extension FlipTear {
    static func seed(itemID: Int, playedAt: Date) -> UInt64 {
        UInt64(bitPattern: Int64(itemID)) &+ UInt64(playedAt.timeIntervalSince1970)
    }

    static func isLastLife(misses: Int, frameCount: Int) -> Bool {
        misses >= max(frameCount - 1, 1)
    }

    static func round(seed: UInt64, attemptsMade: Int, frameCount: Int,
                      outcome: RoundOutcome?, hasLanded: Bool) -> FlipTear {
        switch outcome {
        case .incorrect:
            return FlipTear(seed: seed, progress: 1.1, opening: 0.03, separation: 6)
        case .correct where hasLanded:
            return FlipTear(seed: seed, scar: torn(seed: seed, misses: attemptsMade - 1, frameCount: frameCount).progress)
        case .correct:
            return torn(seed: seed, misses: attemptsMade - 1, frameCount: frameCount)
        case nil:
            var tear = torn(seed: seed, misses: attemptsMade, frameCount: frameCount)
            if attemptsMade > 0, isLastLife(misses: attemptsMade, frameCount: frameCount) { tear.strain = 1 }
            return tear
        }
    }

    private static func torn(seed: UInt64, misses: Int, frameCount: Int) -> FlipTear {
        guard misses > 0 else { return FlipTear(seed: seed) }
        if isLastLife(misses: misses, frameCount: frameCount) {
            return FlipTear(seed: seed, progress: 0.9, opening: 0.05)
        }
        let share = Float(misses) / Float(max(frameCount - 1, 1))
        return FlipTear(seed: seed, progress: 0.14 + 0.42 * pow(share, 1.6), opening: 0.005 + 0.012 * share)
    }
}
