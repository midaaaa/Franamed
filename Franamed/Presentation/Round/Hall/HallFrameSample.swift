//
//  HallFrameSample.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct HallFrameSample: Sendable, Equatable {
    static let columns = 24
    static let rows = 14
    static var cellCount: Int { columns * rows }

    let mean: SIMD3<Float>
    let blurredInterleaved: [Float]

    static let dark = HallFrameSample(mean: .zero, blurredInterleaved: [Float](repeating: 0, count: cellCount * 3))

    private init(mean: SIMD3<Float>, blurredInterleaved: [Float]) {
        self.mean = mean
        self.blurredInterleaved = blurredInterleaved
    }

    nonisolated init?(image: UIImage) {
        guard let cgImage = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }

        let supersample = 4
        let width = Self.columns * supersample
        let height = Self.rows * supersample
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 32,
                                      bytesPerRow: width * 16, space: space, bitmapInfo: info),
              let data = context.data else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = data.bindMemory(to: Float.self, capacity: width * height * 4)
        let weight = 1 / Float(supersample * supersample)
        var red = [Float](repeating: 0, count: Self.cellCount)
        var green = red, blue = red

        for y in 0..<height {
            for x in 0..<width {
                let cell = (y / supersample) * Self.columns + x / supersample
                let pixel = (y * width + x) * 4
                red[cell] += max(0, pixels[pixel]) * weight
                green[cell] += max(0, pixels[pixel + 1]) * weight
                blue[cell] += max(0, pixels[pixel + 2]) * weight
            }
        }

        let count = Float(Self.cellCount)
        mean = SIMD3(red.reduce(0, +), green.reduce(0, +), blue.reduce(0, +)) / count
        blurredInterleaved = Self.blurred(red: red, green: green, blue: blue)
    }

    private nonisolated static func blurred(red: [Float], green: [Float], blue: [Float]) -> [Float] {
        let weights: [Float] = [0.06, 0.24, 0.4, 0.24, 0.06]
        func blur(_ channel: [Float]) -> [Float] {
            var horizontal = channel
            for y in 0..<Self.rows {
                for x in 0..<Self.columns {
                    var sum: Float = 0
                    for (offset, weight) in weights.enumerated() {
                        let sx = min(max(x + offset - 2, 0), Self.columns - 1)
                        sum += channel[y * Self.columns + sx] * weight
                    }
                    horizontal[y * Self.columns + x] = sum
                }
            }
            var result = horizontal
            for y in 0..<Self.rows {
                for x in 0..<Self.columns {
                    var sum: Float = 0
                    for (offset, weight) in weights.enumerated() {
                        let sy = min(max(y + offset - 2, 0), Self.rows - 1)
                        sum += horizontal[sy * Self.columns + x] * weight
                    }
                    result[y * Self.columns + x] = sum
                }
            }
            return result
        }
        let r = blur(red), g = blur(green), b = blur(blue)
        return (0..<Self.cellCount).flatMap { [r[$0], g[$0], b[$0]] }
    }
}

extension HallFrameSample {
    var brightness: Float { (mean.x + mean.y + mean.z) / 3 }

    func withBrightness(_ target: Float) -> HallFrameSample {
        guard brightness > 0 else { return .dark }
        let factor = target / brightness
        return HallFrameSample(mean: mean * factor, blurredInterleaved: blurredInterleaved.map { $0 * factor })
    }

    @MainActor
    static func rendering(_ content: some View) -> HallFrameSample {
        let renderer = ImageRenderer(content: content.frame(width: 320, height: 180))
        renderer.scale = 1
        return renderer.uiImage.flatMap(HallFrameSample.init(image:)) ?? .dark
    }
}
