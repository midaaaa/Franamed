//
//  ProjectorBeamShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.08.2026.
//

import SwiftUI

struct ProjectorBeamShape: Shape {
    var topWidthFraction: CGFloat
    var bottomWidthFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let topHalf = rect.width * topWidthFraction / 2
        let bottomHalf = rect.width * bottomWidthFraction / 2
        let midX = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: midX - topHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: midX + topHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: midX + bottomHalf, y: rect.maxY))
        path.addLine(to: CGPoint(x: midX - bottomHalf, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
