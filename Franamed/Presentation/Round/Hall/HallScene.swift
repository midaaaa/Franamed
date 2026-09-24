//
//  HallScene.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import CoreGraphics
import simd

struct HallScene: Hashable, Sendable {
    static let screenWidth: Float = 18
    static let screenHeight: Float = screenWidth * 9 / 16
    static let screenBottom: Float = 1.0
    static let frontRow: Float = 5
    static let rowArc: Float = 12

    let rowPitch: Float = 1.6
    let rowRise: Float = 0.55
    let rowsInFront = 6
    let eyeHeight: Float = 1.15
    let recline: Float = 0.2
    let seatPitch: Float = 0.95
    let backWidth: Float = 0.72
    let seatTop: Float = 1.02
    let armrestHeight: Float = 0.62
    let armrestWidth: Float = 0.17
    let armrestLength: Float = 0.6
    let armrestSetback: Float = 0.06

    var eye: SIMD3<Float> {
        SIMD3(0, eyeHeight + rowRise * Float(rowsInFront), Self.frontRow + rowPitch * Float(rowsInFront))
    }
}

struct HallCamera {
    let focal: CGFloat
    let principalY: CGFloat

    init(scene: HallScene, frameTop: CGFloat, frameBottom: CGFloat) {
        let eye = scene.eye
        let bottom = (HallScene.screenBottom - eye.y) / eye.z
        let top = (HallScene.screenBottom + HallScene.screenHeight - eye.y) / eye.z
        focal = (frameBottom - frameTop) / CGFloat(top - bottom)
        principalY = frameBottom + focal * CGFloat(bottom)
    }
}
