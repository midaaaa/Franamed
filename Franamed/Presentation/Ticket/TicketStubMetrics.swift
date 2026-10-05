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

    static func height(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGFloat {
        let height = TicketStyle.stubPadding + contentHeight + bottomPadding(width: width, edgeStyle: edgeStyle)
        return (height / 2).rounded(.up) * 2
    }
}

struct TicketStubFrame: ViewModifier {
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle

    func body(content: Content) -> some View {
        content
            .frame(height: TicketStubMetrics.contentHeight, alignment: .top)
            .padding(.top, TicketStyle.stubPadding)
            .padding(.horizontal, TicketStyle.stubPadding)
            .padding(.bottom, TicketStubMetrics.bottomPadding(width: width, edgeStyle: edgeStyle))
            .frame(width: width, height: TicketStubMetrics.height(width: width, edgeStyle: edgeStyle),
                   alignment: .topLeading)
    }
}
