//
//  TicketMotion.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

enum TicketMotion {
    static let minimumDragDistance: CGFloat = 0
    static let commitDistance: CGFloat = 110
    static let flingThreshold: CGFloat = 80
    static let fallbackFlightDistance: CGFloat = 700
    static let flightMargin: CGFloat = 48
    static let flightTiltGain: Double = 1.5
    static let maxTiltDegrees: CGFloat = 6
    static let tiltDivisor: CGFloat = 20

    static let roundCoverIn = Animation.easeOut(duration: 0.2)
    static let returnShrink: CGFloat = 0.05
    static let returnShrinkDuration: TimeInterval = 0.18

    static let snapBack = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let returnRestore = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let flyOut = Animation.linear(duration: 0.22)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.85)
}
