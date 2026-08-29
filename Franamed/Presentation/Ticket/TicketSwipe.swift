//
//  TicketSwipe.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

enum TicketSwipe {

    struct Throw {
        let direction: CGSize
        let changesMode: Bool
        let step: Int
    }

    static func makeThrow(for value: DragGesture.Value) -> Throw? {
        let translation = value.translation
        let predicted = value.predictedEndTranslation
        let dragged = hypot(translation.width, translation.height)
        let fling = hypot(predicted.width - translation.width, predicted.height - translation.height)

        guard dragged >= TicketMotion.commitDistance || fling >= TicketMotion.flingThreshold else {
            return nil
        }

        let vector = dragged > 1 ? translation : predicted
        let magnitude = max(hypot(vector.width, vector.height), 1)
        let direction = CGSize(width: vector.width / magnitude, height: vector.height / magnitude)
        let changesMode = abs(vector.width) >= abs(vector.height)
        let step = changesMode ? (direction.width < 0 ? 1 : -1) : (direction.height < 0 ? 1 : -1)

        return Throw(direction: direction, changesMode: changesMode, step: step)
    }

    static func flightDistance(direction: CGSize, card: CGRect, screen: CGSize) -> CGFloat {
        guard screen != .zero, !card.isEmpty else { return TicketMotion.fallbackFlightDistance }

        var shortest = CGFloat.greatestFiniteMagnitude
        if direction.width < -0.01 {
            shortest = min(shortest, card.maxX / -direction.width)
        }
        if direction.width > 0.01 {
            shortest = min(shortest, (screen.width - card.minX) / direction.width)
        }
        if direction.height < -0.01 {
            shortest = min(shortest, card.maxY / -direction.height)
        }
        if direction.height > 0.01 {
            shortest = min(shortest, (screen.height - card.minY) / direction.height)
        }

        guard shortest != .greatestFiniteMagnitude else { return TicketMotion.fallbackFlightDistance }
        return shortest + TicketMotion.flightMargin
    }

    static func tiltDegrees(for translation: CGSize) -> Double {
        let limit = TicketMotion.maxTiltDegrees
        return Double(min(max(translation.width / TicketMotion.tiltDivisor, -limit), limit))
    }
}
