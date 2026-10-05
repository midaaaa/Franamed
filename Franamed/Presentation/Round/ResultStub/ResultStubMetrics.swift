//
//  ResultStubMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

enum ResultStubMetrics {
    @MainActor
    static func height(edgeStyle: TicketEdgeStyle) -> CGFloat {
        TicketStubMetrics.height(width: width, edgeStyle: edgeStyle)
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
        let edgeStyle = TicketEdgeStyle(hasScallops: hasScallops)

        VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
            content
        }
        .modifier(TicketStubFrame(width: ResultStubMetrics.width, edgeStyle: edgeStyle))
        .background(TicketStyle.paper)
        .clipShape(ResultStubShape(edgeStyle: edgeStyle, mirrored: mirrored))
        .environment(\.colorScheme, .light)
    }
}
