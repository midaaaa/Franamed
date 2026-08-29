//
//  TearPose.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import CoreGraphics

nonisolated struct TearPose {
    var perfOrigin: CGPoint
    var perfDir: CGVector
    var stubN: CGVector
    var perfLength: CGFloat
    var theta: CGFloat
    var apexA: CGFloat
    var offset: CGVector
    var front: CGFloat
    var pitch: CGFloat
    var holeLen: CGFloat
    var patternOrigin: CGFloat
    var patternSign: CGFloat
    var patternInset: CGFloat
    var strainCell: Int
    var strain: CGFloat
    var opacity: CGFloat
}
