//
//  FlipTear.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 03.10.2026.
//

import CoreGraphics
import simd

struct FlipTear: Equatable {
    var seed: UInt64
    var progress: Float = 0
    var opening: Float = 0
    var separation: Float = 0
    var strain: Float = 0
    var scar: Float = 0

    static let none = FlipTear(seed: 0)

    var state: SIMD3<Float> { SIMD3(progress, opening, separation) }

    func shape(width: CGFloat) -> (line: SIMD4<Float>, shape: SIMD4<Float>) {
        var generator = SplitMix(state: seed &+ 0x51_7C_C1_B7_27_22_0A_95)
        let w = Float(width)
        let top = (generator.unit() * 0.3 - 0.15) * w
        let bottom = (generator.unit() * 0.36 - 0.18) * w
        let phaseA = generator.unit() * 6.2832
        let phaseB = generator.unit() * 6.2832
        let amplitudeA = 4 + generator.unit() * 6
        let amplitudeB = 1 + generator.unit() * 2.5
        let noiseSeed = generator.unit() * 97
        let wideSide: Float = generator.unit() < 0.5 ? -1 : 1
        return (SIMD4(top, bottom, phaseA, phaseB), SIMD4(amplitudeA, amplitudeB, noiseSeed, wideSide))
    }
}

private struct SplitMix {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
