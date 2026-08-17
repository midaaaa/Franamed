//
//  ProjectorBeamFill.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.08.2026.
//

import SwiftUI

struct ProjectorBeamFill: View {
    var stripTints: [ProjectorStripTint] = []
    private let topWidthFraction: CGFloat = 1.0
    private let bottomWidthFraction: CGFloat = 0.15
    private let topEdgeFloor: Double = 0.1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ProjectorBeamShape(topWidthFraction: topWidthFraction, bottomWidthFraction: bottomWidthFraction)
                    .fill(fillStyle(size: proxy.size))
                    .mask(sourceFalloffMask(size: proxy.size))
                    .mask(centerBrightnessMask(size: proxy.size))

                Rectangle()
                    .fill(fillStyle(size: proxy.size))
                    .opacity(topEdgeFloor)
                    .frame(width: proxy.size.width * topWidthFraction, height: 14)
                    .offset(y: -14)
            }
        }
        .blur(radius: 3)
    }

    private func sourceFalloffMask(size: CGSize) -> some View {
        let geometry = apexGeometry(size: size)
        return RadialGradient(
            stops: [
                .init(color: .white.opacity(1.0), location: 0.0),
                .init(color: .white.opacity(0.85), location: 0.15),
                .init(color: .white.opacity(0.55), location: 0.3),
                .init(color: .white.opacity(0.3), location: 0.5),
                .init(color: .white.opacity(0.22), location: 0.7),
                .init(color: .white.opacity(0.16), location: 0.85),
                .init(color: .white.opacity(topEdgeFloor), location: 1.0),
            ],
            center: geometry.center,
            startRadius: 0,
            endRadius: geometry.maxRadius
        )
    }

    private func centerBrightnessMask(size: CGSize) -> some View {
        let geometry = apexGeometry(size: size)
        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(0.35), location: 0.0),
                .init(color: .white.opacity(1.0), location: 0.5),
                .init(color: .white.opacity(0.35), location: 1.0),
            ]),
            center: geometry.center,
            startAngle: geometry.startAngle,
            endAngle: geometry.endAngle
        )
    }

    private func apexGeometry(size: CGSize) -> (center: UnitPoint, startAngle: Angle, endAngle: Angle, maxRadius: CGFloat) {
        let topHalf = size.width * topWidthFraction / 2
        let bottomHalf = size.width * bottomWidthFraction / 2
        let midX = size.width / 2
        let denom = topHalf - bottomHalf
        let apexY = denom > 0 ? topHalf / denom * size.height : size.height
        let apex = CGPoint(x: midX, y: apexY)
        let center = UnitPoint(x: apex.x / size.width, y: apex.y / size.height)

        func angle(atXFraction fraction: CGFloat) -> Angle {
            let point = CGPoint(x: fraction * size.width, y: 0)
            return Angle(radians: atan2(point.y - apex.y, point.x - apex.x))
        }

        let topLeft = CGPoint(x: midX - topHalf, y: 0)
        let maxRadius = hypot(topLeft.x - apex.x, topLeft.y - apex.y)

        return (center, angle(atXFraction: 0), angle(atXFraction: 1), maxRadius)
    }

    private func fillStyle(size: CGSize) -> AnyShapeStyle {
        guard stripTints.count >= 2, size.width > 0, size.height > 0 else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.white.opacity(0.15), Color.white.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }

        let geometry = apexGeometry(size: size)
        return AnyShapeStyle(
            AngularGradient(
                gradient: Gradient(stops: rayStops(tints: stripTints)),
                center: geometry.center,
                startAngle: geometry.startAngle,
                endAngle: geometry.endAngle
            )
        )
    }

    private func rayStops(tints: [ProjectorStripTint]) -> [Gradient.Stop] {
        let count = tints.count
        return tints.enumerated().map { index, tint in
            let location = (CGFloat(index) + 0.5) / CGFloat(count)
            let rayIntensity = max(0.35, pow(tint.brightness, 0.7))
            let rayColor = tint.color.opacity(min(1, rayIntensity))
            return .init(color: rayColor, location: location)
        }
    }
}

#Preview("Flat (no tints)") {
    ProjectorBeamFill()
        .frame(width: 260, height: 220)
        .background(Color.black)
}

#Preview("Tinted") {
    ProjectorBeamFill(
        stripTints: (0..<14).map { index in
            let hue = Double(index) / 14
            let brightness = 0.5 + 0.3 * sin(Double(index))
            return ProjectorStripTint(
                color: Color(hue: hue, saturation: 0.6, brightness: 0.8),
                brightness: brightness
            )
        }
    )
    .frame(width: 260, height: 220)
    .background(Color.black)
}
