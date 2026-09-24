//
//  ResultStubShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

struct ResultStubShape: Shape, Hashable {
    var edgeStyle: TicketEdgeStyle = .scalloped
    var mirrored = false

    static func perforation(width: CGFloat) -> TearPerforation {
        TearPerforation(config: .ticket(width: width), length: width)
    }

    func path(in rect: CGRect) -> Path {
        let perforation = Self.perforation(width: rect.width)

        var paper = base(in: rect).subtracting(tornStrip(in: rect, perforation: perforation))

        for notch in earNotches(in: rect) {
            paper = paper.subtracting(notch)
        }

        if edgeStyle == .scalloped {
            for scallop in bottomScallops(in: rect) {
                paper = paper.subtracting(scallop)
            }
        }

        guard mirrored else { return paper }
        return paper.applying(CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0)
            .scaledBy(x: -1, y: 1))
    }

    private func base(in rect: CGRect) -> Path {
        guard edgeStyle == .straight else { return Path(rect) }
        let radius = min(TicketStyle.tearNotchRadius, rect.width / 2, rect.height / 2)
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: radius,
                                              bottomTrailing: radius, topTrailing: 0)
        ).path(in: rect)
    }

    // MARK: Torn top edge

    private func tornStrip(in rect: CGRect, perforation: TearPerforation) -> Path {
        let step: CGFloat = 0.4
        var strip = Path()
        strip.move(to: CGPoint(x: rect.minX - 1, y: rect.minY - 8))
        strip.addLine(to: CGPoint(x: rect.minX - 1, y: rect.minY + cut(at: 0, perforation: perforation)))

        var x = rect.minX
        while x <= rect.maxX {
            strip.addLine(to: CGPoint(x: x, y: rect.minY + cut(at: x - rect.minX, perforation: perforation)))
            x += step
        }

        strip.addLine(to: CGPoint(x: rect.maxX + 1,
                                  y: rect.minY + cut(at: rect.width, perforation: perforation)))
        strip.addLine(to: CGPoint(x: rect.maxX + 1, y: rect.minY - 8))
        strip.closeSubpath()
        return strip
    }

    private func cut(at a: CGFloat, perforation: TearPerforation) -> CGFloat {
        max(slotCut(at: a, perforation: perforation), fractureCut(at: a, perforation: perforation))
    }

    private func slotCut(at a: CGFloat, perforation: TearPerforation) -> CGFloat {
        let halfWidth = perforation.halfWidth
        let half = perforation.holeLength / 2
        let radius = min(halfWidth * perforation.cornerScale, min(half, halfWidth))

        let nearest = abs(offsetToSlotCenter(at: a, perforation: perforation))
        guard nearest <= half else { return 0 }

        let flat = half - radius
        guard nearest > flat else { return halfWidth }
        let corner = nearest - flat
        return (halfWidth - radius) + sqrt(max(radius * radius - corner * corner, 0))
    }

    private func fractureCut(at a: CGFloat, perforation: TearPerforation) -> CGFloat {
        let wander = Self.tearJitter(a, amp: Self.jitterAmplitude) * sin(.pi * tabProgress(at: a, perforation: perforation))
        return max(Self.tornGap + wander, 0.35)
    }

    private func tabProgress(at a: CGFloat, perforation: TearPerforation) -> CGFloat {
        let pitch = max(perforation.pitch, 0.01)
        let cell = (a - perforation.endInset - perforation.tabLength) / pitch
        let holeFraction = min(max(perforation.holeLength / pitch, 0), 0.99)
        let progress = (cell - cell.rounded(.down) - holeFraction) / (1 - holeFraction)
        return min(max(progress, 0), 1)
    }

    private func offsetToSlotCenter(at a: CGFloat, perforation: TearPerforation) -> CGFloat {
        guard perforation.pitch > 0.01 else { return .greatestFiniteMagnitude }
        let first = perforation.holeCenter(0)
        let shifted = (a - first) / perforation.pitch
        return (shifted - shifted.rounded()) * perforation.pitch
    }

    // MARK: Noise, one to one with the shader

    private static let jitterAmplitude: CGFloat = 1.2
    private static let tornGap: CGFloat = 1.0

    private static func hashCell(_ n: CGFloat) -> CGFloat {
        var h = UInt32(max(n, 0))
        h ^= h >> 16
        h &*= 0x7feb352d
        h ^= h >> 15
        h &*= 0x846ca68b
        h ^= h >> 16
        return CGFloat(h >> 8) / 16_777_216
    }

    private static func vnoise(_ x: CGFloat) -> CGFloat {
        let i = x.rounded(.down)
        var f = x - i
        f = f * f * (3 - 2 * f)
        return (hashCell(i) + (hashCell(i + 1) - hashCell(i)) * f) * 2 - 1
    }

    private static func tearJitter(_ a: CGFloat, amp: CGFloat) -> CGFloat {
        amp * (0.55 * vnoise(a * 0.11) + 0.30 * vnoise(a * 0.37) + 0.15 * vnoise(a * 1.30))
    }

    // MARK: Ears and scallops

    private func earNotches(in rect: CGRect) -> [Path] {
        let radius = TicketStyle.tearNotchRadius
        return [rect.minX, rect.maxX].map { x in
            Path(ellipseIn: CGRect(x: x - radius, y: rect.minY - radius,
                                   width: radius * 2, height: radius * 2))
        }
    }

    private func bottomScallops(in rect: CGRect) -> [Path] {
        TicketPerforationShape.scallops(in: rect).map { scallop in
            Path(ellipseIn: CGRect(x: scallop.x - scallop.radius, y: rect.maxY - scallop.radius,
                                   width: scallop.radius * 2, height: scallop.radius * 2))
        }
    }
}

#Preview("Кромка — фестоны") {
    Color.white
        .frame(width: 293, height: 210)
        .clipShape(ResultStubShape(edgeStyle: .scalloped))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}

#Preview("Кромка — лицо против оборота") {
    VStack(spacing: 4) {
        Color.white.frame(width: 293, height: 210)
            .clipShape(ResultStubShape(edgeStyle: .scalloped, mirrored: true))
        Color.white.frame(width: 293, height: 210)
            .clipShape(ResultStubShape(edgeStyle: .scalloped))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

#Preview("Кромка — прямой край") {
    Color.white
        .frame(width: 293, height: 210)
        .clipShape(ResultStubShape(edgeStyle: .straight))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
