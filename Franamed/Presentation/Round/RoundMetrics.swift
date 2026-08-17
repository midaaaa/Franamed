//
//  RoundMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import CoreGraphics

let suggestionRowHeight: CGFloat = 44
let suggestionsLeadingInset: CGFloat = 16
let minVisibleSuggestions = 3
let maxVisibleSuggestions = 6
let suggestionDividerHeight: CGFloat = 1

func suggestionsContentHeight(rows: Int) -> CGFloat {
    guard rows > 0 else { return 0 }
    return suggestionRowHeight * CGFloat(rows) + suggestionDividerHeight * CGFloat(rows - 1)
}
