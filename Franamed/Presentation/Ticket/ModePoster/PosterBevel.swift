//
//  PosterBevel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import os
import SwiftUI
import simd

struct PosterBevel<S: Shape>: View {
    let shape: S
    let id: String
    let size: CGSize
    let radius: CGFloat
    let depth: CGFloat
    let strength: CGFloat
    let tilt: SIMD2<Float>
    let posterSize: CGSize
    let origin: CGPoint

    @Environment(\.displayScale) private var displayScale
    @State private var baked: Baked?

    var body: some View {
        let key = key
        ZStack {
            if let map = baked?.key == key ? baked?.map : PosterBevelMaps.cached(key) {
                shape
                    .fill(.white)
                    .colorEffect(ShaderLibrary.posterBevel(.image(Image(decorative: map, scale: 1)), .float2(size),
                                                           .float2(tilt.x, tilt.y), .float(strength),
                                                           .float2(posterSize), .float2(origin)))
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: key) {
            guard PosterBevelMaps.cached(key) == nil else { return }
            let path = PosterBevelMaps.Outline(path: shape.path(in: CGRect(origin: .zero, size: size)).cgPath)
            guard let map = await PosterBevelMaps.map(for: key, outline: path) else { return }
            baked = Baked(key: key, map: map)
        }
    }

    private var key: PosterBevelMaps.Key {
        PosterBevelMaps.Key(id: id, size: size, radius: radius, depth: depth, scale: displayScale)
    }

    private struct Baked {
        let key: PosterBevelMaps.Key
        let map: CGImage
    }
}

enum PosterBevelMaps {
    struct Key: Hashable, Sendable {
        let id: String
        let size: CGSize
        let radius: CGFloat
        let depth: CGFloat
        let scale: CGFloat

        var name: NSString { "\(id)|\(size.width)x\(size.height)|\(radius)|\(depth)|\(scale)" as NSString }
    }

    struct Outline: @unchecked Sendable {
        let path: CGPath
    }

    private nonisolated(unsafe) static let maps = NSCache<NSString, CGImage>()
    private nonisolated static let inFlight = OSAllocatedUnfairLock(initialState: [Key: Task<CGImage?, Never>]())

    nonisolated static func cached(_ key: Key) -> CGImage? {
        maps.object(forKey: key.name)
    }

    nonisolated static func map(for key: Key, outline: Outline) async -> CGImage? {
        let task = inFlight.withLock { running in
            if let task = running[key] { return task }
            let task = Task.detached(priority: .userInitiated) {
                let map = bake(outline.path, key: key)
                if let map { maps.setObject(map, forKey: key.name) }
                return map
            }
            running[key] = task
            return task
        }
        let map = await task.value
        inFlight.withLock { $0[key] = nil }
        return map
    }

    // MARK: Baking

    private nonisolated static func bake(_ path: CGPath, key: Key) -> CGImage? {
        let width = Int((key.size.width * key.scale).rounded(.up))
        let height = Int((key.size.height * key.scale).rounded(.up))
        guard width > 2, height > 2 else { return nil }
        let padded = (width: width + 2, height: height + 2)

        var coverage = [UInt8](repeating: 0, count: padded.width * padded.height)
        let drawn = coverage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: padded.width, height: padded.height,
                                          bitsPerComponent: 8, bytesPerRow: padded.width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.translateBy(x: 1, y: CGFloat(padded.height - 1))
            context.scaleBy(x: key.scale, y: -key.scale)
            context.addPath(path)
            context.setFillColor(gray: 1, alpha: 1)
            context.fillPath()
            return true
        }
        guard drawn else { return nil }

        let distance = edgeDistances(coverage, width: padded.width, height: padded.height)
        func at(_ x: Int, _ y: Int) -> Float { distance[(y + 1) * padded.width + x + 1] }
        let radius = Float(key.radius * key.scale)
        let depth = Float(key.depth)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = 128
                pixels[i + 1] = 128
                let d = at(x, y)
                guard coverage[(y + 1) * padded.width + x + 1] > 0, d < radius else { continue }
                let gx = at(x + 1, y) - at(x - 1, y)
                let gy = at(x, y + 1) - at(x, y - 1)
                let pull = (gx * gx + gy * gy).squareRoot()
                guard pull > 1e-3 else { continue }
                let rise = 1 - d / radius
                let slope = rise / (Float(key.radius) * max((1 - rise * rise).squareRoot(), 0.15))
                let tangent = SIMD2(-gx, -gy) / pull * slope * depth
                let normal = simd_normalize(SIMD3(tangent.x, tangent.y, 1))
                pixels[i] = UInt8(clamping: Int(((normal.x * 0.5 + 0.5) * 255).rounded()))
                pixels[i + 1] = UInt8(clamping: Int(((normal.y * 0.5 + 0.5) * 255).rounded()))
                pixels[i + 2] = 255
            }
        }

        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }

    private nonisolated static func edgeDistances(_ coverage: [UInt8], width: Int, height: Int) -> [Float] {
        let far = Float(width * width + height * height)
        var squared = coverage.map { $0 > 0 ? far : 0 }
        var line = [Float](repeating: 0, count: max(width, height))
        var result = line
        for x in 0..<width {
            for y in 0..<height { line[y] = squared[y * width + x] }
            transform(line, count: height, into: &result)
            for y in 0..<height { squared[y * width + x] = result[y] }
        }
        for y in 0..<height {
            for x in 0..<width { line[x] = squared[y * width + x] }
            transform(line, count: width, into: &result)
            for x in 0..<width { squared[y * width + x] = result[x] }
        }
        return squared.map { max($0.squareRoot() - 0.5, 0) }
    }

    private nonisolated static func transform(_ f: [Float], count: Int, into d: inout [Float]) {
        var v = [Int](repeating: 0, count: count)
        var z = [Float](repeating: 0, count: count + 1)
        func meet(_ q: Int, _ p: Int) -> Float {
            ((f[q] + Float(q * q)) - (f[p] + Float(p * p))) / Float(2 * (q - p))
        }
        var k = 0
        z[0] = -.infinity
        z[1] = .infinity
        for q in 1..<count {
            var s = meet(q, v[k])
            while s <= z[k] {
                k -= 1
                s = meet(q, v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .infinity
        }
        k = 0
        for q in 0..<count {
            while z[k + 1] < Float(q) { k += 1 }
            let p = v[k]
            d[q] = Float((q - p) * (q - p)) + f[p]
        }
    }
}
