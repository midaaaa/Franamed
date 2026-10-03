//
//  ResultStubLight.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.09.2026.
//

import SwiftUI

enum ResultStubLight {
    private static let luma = SIMD3<Float>(0.2126, 0.7152, 0.0722)
    private static let maxAmount: Float = 0.5
    private static let maxChannel: Float = 1.6
    private static let tuckedDarkExposure: Float = 0.38
    private static let openDarkExposure: Float = 0.6

    static func lighting(hallMean mean: SIMD3<Float>, reveal: Float) -> FlipLighting {
        let darkExposure = tuckedDarkExposure + (openDarkExposure - tuckedDarkExposure) * min(max(reveal, 0), 1)
        let luminance = max((mean * luma).sum(), 0)
        let presence = smoothstep(0, 0.12, luminance)
        guard luminance > 1e-4 else {
            return FlipLighting(tint: .one, amount: 0, exposure: darkExposure)
        }
        let chroma = (mean / luminance).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: maxChannel))
        let encoded = SIMD3(pow(chroma.x, 1 / 2.2), pow(chroma.y, 1 / 2.2), pow(chroma.z, 1 / 2.2))
        return FlipLighting(tint: encoded,
                            amount: maxAmount * presence,
                            exposure: darkExposure + (1 - darkExposure) * smoothstep(0.01, 0.12, luminance))
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct ResultStubTiltLight: ViewModifier, Animatable {
    var animatableData: Double
    let maxTilt: Double
    let hallMean: SIMD3<Float>
    let sheenScale: Float

    func body(content: Content) -> some View {
        var lighting = ResultStubLight.lighting(hallMean: hallMean, reveal: Float(1 - animatableData / maxTilt))
        lighting.sheenScale = sheenScale
        return content
            .environment(\.flipTilt, animatableData)
            .environment(\.flipLighting, lighting)
    }
}
