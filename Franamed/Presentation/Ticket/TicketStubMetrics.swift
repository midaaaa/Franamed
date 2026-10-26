//
//  TicketStubMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 05.10.2026.
//

import SwiftUI

enum TicketStubMetrics {
    static let contentHeight: CGFloat = 189
    private static let scallopGap: CGFloat = 6

    static func bottomPadding(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGFloat {
        switch edgeStyle {
        case .straight: TicketStyle.stubPadding
        case .scalloped: TicketPerforationShape.scallopDepth(width: width) + scallopGap
        }
    }

    static func serialOffset(edgeStyle: TicketEdgeStyle) -> CGFloat {
        let width = TicketStyle.referenceWidth
        let edgeDepth = edgeStyle == .scalloped ? TicketPerforationShape.scallopDepth(width: width) : 0
        let band = contentHeight - TicketStyle.stubBodyHeight + bottomPadding(width: width, edgeStyle: edgeStyle) - edgeDepth
        return band / 2
    }

    static func height(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGFloat {
        let height = layoutHeight(edgeStyle: edgeStyle) * TicketStyle.zoom(forWidth: width)
        return (height / 2).rounded(.up) * 2
    }

    private static func layoutHeight(edgeStyle: TicketEdgeStyle) -> CGFloat {
        TicketStyle.stubPadding + contentHeight + bottomPadding(width: TicketStyle.referenceWidth, edgeStyle: edgeStyle)
    }
}

struct TicketStubFrame: ViewModifier {
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle

    func body(content: Content) -> some View {
        let layoutWidth = TicketStyle.referenceWidth
        content
            .environment(\.ticketEdgeStyle, edgeStyle)
            .frame(height: TicketStubMetrics.contentHeight, alignment: .top)
            .padding(.top, TicketStyle.stubPadding)
            .padding(.horizontal, TicketStyle.stubPadding)
            .padding(.bottom, TicketStubMetrics.bottomPadding(width: layoutWidth, edgeStyle: edgeStyle))
            .frame(width: layoutWidth, alignment: .topLeading)
            .scaleEffect(TicketStyle.zoom(forWidth: width), anchor: .topLeading)
            .frame(width: width, height: TicketStubMetrics.height(width: width, edgeStyle: edgeStyle),
                   alignment: .topLeading)
    }
}

extension EnvironmentValues {
    @Entry var ticketEdgeStyle = TicketEdgeStyle.straight
}
