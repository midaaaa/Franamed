//
//  FlipPanGestureRecognizer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import UIKit

final class FlipPanGestureRecognizer: UIPanGestureRecognizer {
    var onTouchesBegan: (() -> Void)?
    var onTouchSample: ((TimeInterval, CGFloat) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouchesBegan?()
        record(touches, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        record(touches, event: event)
    }

    private func record(_ touches: Set<UITouch>, event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            onTouchSample?(sample.timestamp, sample.location(in: view).x)
        }
    }
}
