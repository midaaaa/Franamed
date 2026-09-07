//
//  SuggestionsHitTestContainer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.09.2026.
//

import UIKit

final class SuggestionsHitTestContainer: UIView {
    var visibleHeight: CGFloat = 0

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard point.y >= bounds.height - visibleHeight else { return nil }
        return super.hitTest(point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.forEach { $0.frame = bounds }
    }
}
