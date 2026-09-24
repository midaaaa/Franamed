//
//  StubShake.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

struct StubShake: GeometryEffect {
    static let duration: Double = 0.42

    var travel: CGFloat = 12
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard animatableData > 0, animatableData < 1 else { return ProjectionTransform(.identity) }
        let decay = pow(1 - animatableData, 0.7)
        let offset = travel * decay * sin(animatableData * .pi * 2 * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
