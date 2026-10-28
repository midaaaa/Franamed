//
//  ResultStubTear.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 09.10.2026.
//

import Foundation

extension FlipTear {
    static func randomSeed() -> UInt64 {
        .random(in: 1 ... .max)
    }

    static func seed(ticket: UInt64, round: Int) -> UInt64 {
        guard round > 0 else { return ticket }
        var generator = SplitMix(state: ticket &+ UInt64(round))
        return max(generator.next(), 1)
    }

    static func seed(uid: String, playlistID: String, mediaKey: String) -> UInt64 {
        PlaylistSeed.hash("\(uid):\(playlistID):\(mediaKey)")
    }

    static func isLastLife(misses: Int, frameCount: Int) -> Bool {
        misses >= frameCount - 1
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
            if isLastLife(misses: attemptsMade, frameCount: frameCount) { tear.strain = 1 }
            return tear
        }
    }

    private static func torn(seed: UInt64, misses: Int, frameCount: Int) -> FlipTear {
        if isLastLife(misses: misses, frameCount: frameCount) {
            return FlipTear(seed: seed, progress: 0.9, opening: 0.05)
        }
        guard misses > 0 else { return FlipTear(seed: seed) }
        let share = Float(misses) / Float(max(frameCount - 1, 1))
        return FlipTear(seed: seed, progress: 0.14 + 0.42 * pow(share, 1.6), opening: 0.005 + 0.012 * share)
    }
}

extension PlaylistTicket {
    func tearSeed(for mediaKey: String) -> UInt64? {
        uid.map { FlipTear.seed(uid: $0, playlistID: id, mediaKey: mediaKey) }
    }
}
