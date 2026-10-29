//
//  ResultStubMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

enum ResultStubMetrics {
    static func size(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGSize {
        CGSize(width: width, height: TicketStubMetrics.height(width: width, edgeStyle: edgeStyle))
    }
}

struct ResultStubPaper<Content: View>: View {
    var mirrored = false
    var clipsShape = true
    var edge = TearEdge.plain
    var ink = TicketInk.light
    @ViewBuilder let content: Content

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @Environment(\.resultStubWidth) private var stubWidth

    var body: some View {
        let edgeStyle = TicketEdgeStyle(hasScallops: hasScallops)

        content
            .modifier(TicketStubFrame(width: stubWidth, edgeStyle: edgeStyle))
            .background(ink.paper)
            .clipShape(clipsShape ? AnyShape(ResultStubShape(edgeStyle: edgeStyle, mirrored: mirrored, edge: edge)) : AnyShape(Rectangle()))
            .environment(\.colorScheme, .light)
    }
}

extension EnvironmentValues {
    @Entry var resultStubWidth = TicketStyle.referenceWidth
}
