//
//  EdgeOutline.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import CoreGraphics
import simd

nonisolated enum EdgeOutline {
    typealias Vertex = SIMD4<Float>

    struct Outline: Equatable {
        var vertices: [Vertex] = []
        var ranges: [Range<Int>] = []
    }

    static func outline(of path: CGPath, mapping: (CGPoint) -> CGPoint = { $0 }) -> Outline {
        var outline = Outline()
        for contour in contours(of: path) {
            let mapped = contour.map(mapping)
            let start = outline.vertices.count
            let winding: CGFloat = signedArea(mapped) >= 0 ? 1 : -1

            for (index, point) in mapped.enumerated() {
                let previous = mapped[(index + mapped.count - 1) % mapped.count]
                let next = mapped[(index + 1) % mapped.count]
                var tangent = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
                let length = max(hypot(tangent.x, tangent.y), 0.0001)
                tangent.x /= length
                tangent.y /= length

                outline.vertices.append(Vertex(
                    Float(point.x), Float(point.y),
                    Float(tangent.y * winding), Float(-tangent.x * winding)
                ))
            }
            outline.ranges.append(start..<outline.vertices.count)
        }
        return outline
    }

    // MARK: Flattening

    private static func contours(of path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero
        var last = CGPoint.zero

        func flush() {
            if current.count > 2 { result.append(resampled(deduplicated(current))) }
            current = []
        }

        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                flush()
                current = [points[0]]
                start = points[0]
                last = points[0]
            case .addLineToPoint:
                current.append(points[0])
                last = points[0]
            case .addQuadCurveToPoint:
                for step in 1...quadSteps {
                    let t = CGFloat(step) / CGFloat(quadSteps)
                    current.append(quad(last, points[0], points[1], t))
                }
                last = points[1]
            case .addCurveToPoint:
                for step in 1...curveSteps {
                    let t = CGFloat(step) / CGFloat(curveSteps)
                    current.append(cubic(last, points[0], points[1], points[2], t))
                }
                last = points[2]
            case .closeSubpath:
                flush()
                last = start
            @unknown default:
                break
            }
        }
        flush()
        return result.filter { $0.count > 2 }
    }

    private static let quadSteps = 8
    private static let curveSteps = 10
    private static let maxSegment: CGFloat = 2

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * b.x + t * t * c.x,
                       y: u * u * a.y + 2 * u * t * b.y + t * t * c.y)
    }

    private static func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint,
                              _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        return CGPoint(x: w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x,
                       y: w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y)
    }

    private static func resampled(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            result.append(a)
            let steps = Int((hypot(b.x - a.x, b.y - a.y) / maxSegment).rounded(.down))
            guard steps > 1 else { continue }
            for step in 1..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return result
    }

    private static func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(point.x - last.x, point.y - last.y) < 0.01 { continue }
            result.append(point)
        }
        if let first = result.first, let last = result.last,
           result.count > 1, hypot(first.x - last.x, first.y - last.y) < 0.01 {
            result.removeLast()
        }
        return result
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}
