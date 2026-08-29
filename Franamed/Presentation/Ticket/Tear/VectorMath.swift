//
//  VectorMath.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import CoreGraphics

infix operator •: MultiplicationPrecedence

nonisolated extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
    static func + (a: CGPoint, b: CGVector) -> CGPoint { CGPoint(x: a.x + b.dx, y: a.y + b.dy) }
}

nonisolated extension CGVector {
    static func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static prefix func - (v: CGVector) -> CGVector { CGVector(dx: -v.dx, dy: -v.dy) }
    static func • (a: CGVector, b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
}

nonisolated func easeOutCubic(_ t: Double) -> Double {
    let u = 1 - min(max(t, 0), 1)
    return 1 - u * u * u
}

nonisolated func easeInOutCubic(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    if x < 0.5 { return 4 * x * x * x }
    let u = -2 * x + 2
    return 1 - u * u * u / 2
}
