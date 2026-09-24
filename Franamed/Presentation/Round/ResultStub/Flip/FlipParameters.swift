//
//  FlipParameters.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import Foundation

struct FlipParameters {
    var response: Double = 0.5
    var damping: Double = 0.92
    var projection: Double = 0.10
    var bendGain: Double = 0.07
    var bendMax: Double = 0.2
    var bendTau: Double = 0.07
}

enum FlipLook {
    static let perspective: Float = 900
    static let sheen: Float = 1.0
    static let gloss: Float = 26
    static let canvasPadding: CGFloat = 44
}
