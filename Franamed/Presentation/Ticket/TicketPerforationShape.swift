//
//  TicketPerforationShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

struct TicketPerforationShape: Shape {
    var tearLineOffset: CGFloat?
    var tearLineSlots: TearPerforation?
    var scallopedEdges: VerticalEdge.Set = .all
    var tearNotchEdges: VerticalEdge.Set = []

    var tabCount: Int = 10
    var cornerScallopScale: CGFloat = 1.6
    var scallopFillRatio: CGFloat = 0.8

    var tearNotchRadius: CGFloat = TicketStyle.tearNotchRadius

    func path(in rect: CGRect) -> Path {
        var cuts = Path()

        for scallop in scallops(in: rect) {
            if scallopedEdges.contains(.top) {
                cuts.addCircle(x: scallop.x, y: rect.minY, radius: scallop.radius)
            }
            if scallopedEdges.contains(.bottom) {
                cuts.addCircle(x: scallop.x, y: rect.maxY, radius: scallop.radius)
            }
        }

        if let tearLineOffset {
            let y = rect.minY + tearLineOffset
            addTearNotches(to: &cuts, in: rect, y: y)
            if let tearLineSlots {
                addTearSlots(to: &cuts, in: rect, y: y, pattern: tearLineSlots)
            }
        }
        if tearNotchEdges.contains(.top) {
            addTearNotches(to: &cuts, in: rect, y: rect.minY)
        }
        if tearNotchEdges.contains(.bottom) {
            addTearNotches(to: &cuts, in: rect, y: rect.maxY)
        }

        return Path(rect).subtracting(cuts)
    }

    private func addTearSlots(to cuts: inout Path, in rect: CGRect, y: CGFloat,
                              pattern: TearPerforation) {
        let depth = pattern.halfWidth
        let radius = min(pattern.halfWidth * pattern.cornerScale, depth)
        let bottom = y + depth
        for index in 0..<pattern.holeCount {
            let center = rect.minX + pattern.holeCenter(index)
            let left = center - pattern.holeLength / 2
            let right = center + pattern.holeLength / 2
            var slot = Path()
            slot.move(to: CGPoint(x: left, y: y))
            slot.addLine(to: CGPoint(x: right, y: y))
            slot.addLine(to: CGPoint(x: right, y: bottom - radius))
            slot.addQuadCurve(to: CGPoint(x: right - radius, y: bottom),
                              control: CGPoint(x: right, y: bottom))
            slot.addLine(to: CGPoint(x: left + radius, y: bottom))
            slot.addQuadCurve(to: CGPoint(x: left, y: bottom - radius),
                              control: CGPoint(x: left, y: bottom))
            slot.closeSubpath()
            cuts.addPath(slot)
        }
    }

    private func addTearNotches(to cuts: inout Path, in rect: CGRect, y: CGFloat) {
        cuts.addCircle(x: rect.minX, y: y, radius: tearNotchRadius)
        cuts.addCircle(x: rect.maxX, y: y, radius: tearNotchRadius)
    }

    private struct Scallop {
        let x: CGFloat
        let radius: CGFloat
    }

    private func scallops(in rect: CGRect) -> [Scallop] {
        let interior = max(tabCount - 1, 2)
        let inset = 1 + scallopFillRatio / 2 * (cornerScallopScale - 1)
        let step = rect.width / (CGFloat(interior - 1) + 2 * inset)
        let radius = step / 2 * scallopFillRatio
        let cornerRadius = radius * cornerScallopScale
        let firstCenter = rect.minX + step * inset

        var result = [Scallop(x: rect.minX, radius: cornerRadius)]
        result += (0..<interior).map {
            Scallop(x: firstCenter + step * CGFloat($0), radius: radius)
        }
        result.append(Scallop(x: rect.maxX, radius: cornerRadius))
        return result
    }
}

private extension Path {
    mutating func addCircle(x: CGFloat, y: CGFloat, radius: CGFloat) {
        addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
}

#Preview("Перфорация") {
    Color.white
        .frame(width: 260, height: 420)
        .mask(TicketPerforationShape(tearLineOffset: 300))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
