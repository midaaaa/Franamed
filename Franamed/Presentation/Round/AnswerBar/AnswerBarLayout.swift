//
//  AnswerBarLayout.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 31.10.2026.
//

import UIKit

enum AnswerBarLayout {
    static let focusedInset: CGFloat = 6
    static let restingInset: CGFloat = 24
    static let suggestionsTopMargin: CGFloat = 8

    static func suggestionsRestRows(windowHeight: CGFloat) -> Int {
        switch windowHeight {
        case ..<1000: minVisibleSuggestions
        case ..<1250: minVisibleSuggestions + 1
        default: minVisibleSuggestions + 2
        }
    }

    static func suggestionsMaxHeight(measuredBarBottom measured: CGFloat, fullHeight: CGFloat, homeIndicatorInset: CGFloat) -> CGFloat {
        let barBottom = measured > 0 ? measured : fullHeight - (restingInset - homeIndicatorInset)
        let available = barBottom - suggestionRowHeight - suggestionsTopMargin
        return max(suggestionsContentHeight(rows: minVisibleSuggestions), available.rounded(.down))
    }

    static func keyboardLift(forHeight height: CGFloat) -> CGFloat {
        height > 0 ? max(0, height + focusedInset - restingInset) : 0
    }

    @MainActor
    static func dockedKeyboardHeight(screenFrame: CGRect, in window: UIWindow?) -> CGFloat {
        guard let window, let screen = window.windowScene?.screen,
              screenFrame.width >= screen.bounds.width - 1 else { return 0 }
        let frame = window.convert(screenFrame, from: screen.coordinateSpace)
        guard frame.maxY >= window.bounds.maxY - 1 else { return 0 }
        return max(0, window.bounds.maxY - frame.minY)
    }

    @MainActor
    static func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
