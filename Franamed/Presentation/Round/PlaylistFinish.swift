//
//  PlaylistFinish.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.10.2026.
//

import Foundation

enum PlaylistFinish: Equatable {
    case played
    case perfect
}

extension PlaylistTicket {
    func answering(isCorrect: Bool) -> PlaylistTicket {
        let answered = isFinished ? self.answered : min(self.answered + 1, total)
        let correct = min(self.correct + (isCorrect ? 1 : 0), total)
        return PlaylistTicket(id: id, title: title, coverURL: coverURL, total: total, answered: answered,
                              correct: correct, isFinished: answered >= total, stampProgress: stampProgress,
                              isStampGold: isStampGold, uid: uid)
    }

    var correctPercent: Int {
        guard total > 0, correct < total else { return 100 }
        return min(99, Int((Double(correct) / Double(total) * 100).rounded()))
    }

    func finish(comparedTo before: PlaylistTicket) -> PlaylistFinish? {
        guard isFinished else { return nil }
        if isPerfect, !before.isFinished || !before.isPerfect { return .perfect }
        return before.isFinished ? nil : .played
    }
}
