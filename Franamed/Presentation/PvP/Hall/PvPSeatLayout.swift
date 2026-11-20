//
//  PvPSeatLayout.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import CoreGraphics
import simd

/// Places rival avatars on the two rows in front of you, using the same camera the Metal hall uses.
/// Rivals are numbered 1…7 (you are not counted):
/// - the closest row: 1 on the left, 2 on the right — sitting on the seat backs;
/// - the next row, left to right: 6 · 3 · 5 · 4 · 7 — floating just above the seats,
///   so they clear both the closest row and the screen.
/// A duel rival always sits in the closest left seat.
struct PvPSeatLayout {
    struct Seat: Equatable {
        let center: CGPoint
        let size: CGFloat
    }

    private struct Place {
        let row: Int
        let x: Float
    }

    static let nearSize: CGFloat = 40
    static let farSize: CGFloat = 26
    static let duelSize: CGFloat = 48
    /// Name labels are kept this wide so neighbours don't collide.
    static let minSpacing: CGFloat = 54

    private static let headrest: Float = 1.06
    private static let seatBack: Float = 0.8
    private static let floatGap: CGFloat = 3
    private static let edgeInset: CGFloat = 4

    /// Seat order for rivals 1…7: the two closest seats, then the second row as 6 · 3 · 5 · 4 · 7.
    private static func place(_ index: Int, pitch: Float) -> Place {
        switch index {
        case 0: Place(row: 0, x: -pitch / 2)
        case 1: Place(row: 0, x: pitch / 2)
        case 2: Place(row: 1, x: -pitch)
        case 3: Place(row: 1, x: pitch)
        case 4: Place(row: 1, x: 0)
        case 5: Place(row: 1, x: -pitch * 2)
        default: Place(row: 1, x: pitch * 2)
        }
    }

    /// Seat centres, in rival order, in the space where the frame spans `0...frameHeight` vertically.
    static func seats(count: Int, isDuel: Bool, frameHeight: CGFloat, frameMidX: CGFloat, width: CGFloat,
                      scene: HallScene = HallScene()) -> [Seat] {
        guard count > 0, frameHeight > 0 else { return [] }
        let camera = HallCamera(scene: scene, frameTop: 0, frameBottom: frameHeight)
        let eye = scene.eye
        let focal = Float(camera.focal)
        let center = SIMD2(Float(frameMidX), Float(camera.principalY))

        func project(row: Int, x: Float, height: Float) -> CGPoint {
            let distance = eye.z - scene.rowPitch * Float(row + 1)
            let radius = distance + HallScene.rowArc
            let z = distance - x * x / (2 * radius)
            let floorY = scene.rowRise * Float(scene.rowsInFront - row - 1)
            let p = HallPhoneDraw.project(SIMD3(x, floorY + height, z), eye: eye, focal: focal, center: center)
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }

        func floating(_ point: CGPoint, size: CGFloat) -> Seat {
            let half = size / 2
            let x = min(max(point.x, half + edgeInset), width - half - edgeInset)
            return Seat(center: CGPoint(x: x, y: point.y - half - floatGap), size: size)
        }

        if isDuel {
            // The rival always takes the closest seat on the left.
            return [Seat(center: project(row: 0, x: -scene.seatPitch / 2, height: seatBack), size: duelSize)]
        }

        return (0..<min(count, 7)).map { index in
            let place = place(index, pitch: scene.seatPitch)
            if place.row == 0 {
                return Seat(center: project(row: 0, x: place.x, height: seatBack), size: nearSize)
            }
            return floating(project(row: 1, x: place.x, height: headrest), size: farSize)
        }
    }
}
