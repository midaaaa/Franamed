//
//  CurlUniforms.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import simd

struct CurlUniforms {
    var projection: simd_float4x4
    var lightDir: SIMD4<Float>

    // MARK: Curl geometry (consumed by the vertex shader)

    var perfOriginX: Float
    var perfOriginY: Float
    var perfDirX: Float
    var perfDirY: Float

    var stubNX: Float
    var stubNY: Float
    var offsetX: Float
    var offsetY: Float

    var ticketWidth: Float
    var ticketHeight: Float
    var apexA: Float
    var theta: Float

    var perfLength: Float
    var stubExtent: Float
    var canvasPadding: Float
    var colsA: Float

    var colsB: Float
    var opacity: Float = 1
    var _reserved1: Float = 0
    var _reserved2: Float = 0

    // MARK: Perforation pattern (consumed by the fragment shader)

    var front: Float
    var pitch: Float
    var holeLen: Float
    var holeHalfWidth: Float

    var jitterAmp: Float
    var strainCell: Float
    var strain: Float
    var neckFraction: Float

    var sheen: Float
    var patternOrigin: Float
    var patternSign: Float
    var patternInset: Float

    var crackWidth: Float
    var tornSoftness: Float
    var slotCorner: Float
    var tornGap: Float

    var paperBack: SIMD4<Float>
}
