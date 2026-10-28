//
//  TicketPanGesture.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import SwiftUI
import UIKit

struct TicketPanGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let canStart: (CGPoint) -> Bool
    let onChange: (CGSize) -> Void
    let onEnd: (_ translation: CGSize, _ velocity: CGSize) -> Void

    final class Coordinator {
        var isTracking = false
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        UIPanGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = CGSize(context.converter.localTranslation ?? .zero)
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            let location = context.converter.localLocation
            let start = CGPoint(x: location.x - translation.width, y: location.y - translation.height)
            coordinator.isTracking = isEnabled && canStart(start)
            if coordinator.isTracking { onChange(translation) }
        case .changed:
            if coordinator.isTracking { onChange(translation) }
        case .ended, .cancelled, .failed:
            guard coordinator.isTracking else { return }
            coordinator.isTracking = false
            onEnd(translation, CGSize(context.converter.localVelocity ?? .zero))
        default:
            break
        }
    }
}

private extension CGSize {
    init(_ point: CGPoint) {
        self.init(width: point.x, height: point.y)
    }
}
