//
//  ResultStubMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

enum ResultStubMetrics {
    static let height: CGFloat = 210
    static let tornInset: CGFloat = 6

    @MainActor
    static var scallopInset: CGFloat {
        TicketPerforationShape.scallopDepth(width: width)
    }

    @MainActor
    static var width: CGFloat {
        max(200, WindowMetrics.size.width - TicketStyle.screenInset * 2)
    }
}

struct ResultStubPaper<Content: View>: View {
    var mirrored = false
    @ViewBuilder let content: Content

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.top, TicketStyle.stubPadding + ResultStubMetrics.tornInset)
        .padding(.bottom, TicketStyle.stubPadding
                 + (hasScallops ? ResultStubMetrics.scallopInset : 0))
        .padding(.horizontal, TicketStyle.stubPadding)
        .frame(width: ResultStubMetrics.width,
               height: ResultStubMetrics.height,
               alignment: .topLeading)
        .background(TicketStyle.paper)
        .clipShape(ResultStubShape(edgeStyle: TicketEdgeStyle(hasScallops: hasScallops),
                                   mirrored: mirrored))
        .environment(\.colorScheme, .light)
    }
}
