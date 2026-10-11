//
//  ResultStubShake.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

struct ResultStubShake: GeometryEffect {
    static let duration: Double = 0.42

    var progress: CGFloat
    var strength: CGFloat = 1
    var travel: CGFloat = 12
    var shakes: CGFloat = 3

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, strength) }
        set { (progress, strength) = (newValue.first, newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard progress > 0, progress < 1 else { return ProjectionTransform(.identity) }
        let decay = pow(1 - progress, 0.7)
        let offset = travel * strength * decay * sin(progress * .pi * 2 * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
