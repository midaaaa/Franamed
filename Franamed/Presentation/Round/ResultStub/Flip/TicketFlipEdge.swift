//
//  TicketFlipEdge.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import SwiftUI

enum TicketFlipEdge {
    typealias Vertex = EdgeOutline.Vertex
    typealias Outline = EdgeOutline.Outline

    static func outline(size: CGSize, edgeStyle: TicketEdgeStyle) -> Outline {
        guard size.width > 1, size.height > 1 else { return Outline() }

        let shape = ResultStubShape(edgeStyle: edgeStyle, mirrored: true)
        let rect = CGRect(origin: .zero, size: size)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        return EdgeOutline.outline(of: shape.path(in: rect).cgPath) {
            CGPoint(x: $0.x - centre.x, y: $0.y - centre.y)
        }
    }
}
