//
//  KeyboardAnimation.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.09.2026.
//

import SwiftUI
import UIKit

enum KeyboardAnimation {
    static func from(_ notification: Notification) -> Animation {
        let info = notification.userInfo
        let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 7
        let points = controlPoints(for: curve)
        return .timingCurve(points.0, points.1, points.2, points.3, duration: duration)
    }

    private static func controlPoints(for curve: Int) -> (Double, Double, Double, Double) {
        switch UIView.AnimationCurve(rawValue: curve) {
        case .easeInOut: (0.42, 0, 0.58, 1)
        case .easeIn: (0.42, 0, 1, 1)
        case .easeOut: (0, 0, 0.58, 1)
        case .linear: (0, 0, 1, 1)
        default: (0.38, 0.7, 0.125, 1)
        }
    }
}
