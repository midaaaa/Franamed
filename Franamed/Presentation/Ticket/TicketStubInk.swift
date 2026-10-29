//
//  TicketStubInk.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.10.2026.
//

import SwiftUI

struct TicketInk: Hashable {
    let paper: Color
    let ink: Color
    let isPrint: Bool

    private static let printPaper = SIMD3<Float>(0.165, 0.165, 0.18)
    private static let printCore = printPaper * 0.55

    static let light = TicketInk(paper: TicketStyle.paper, ink: .black, isPrint: false)
    static let print = TicketInk(paper: Color(red: Double(printPaper.x), green: Double(printPaper.y), blue: Double(printPaper.z)),
                                 ink: Color(white: 0.92), isPrint: true)

    static func stub(for mediaType: MediaType) -> TicketInk {
        mediaType == .tv ? .print : .light
    }

    var core: SIMD3<Float> { isPrint ? Self.printCore : SIMD3(repeating: 0.9) }

    var placeholder: Color { ink.opacity(0.32) }
}

extension EnvironmentValues {
    @Entry var ticketInk = TicketInk.light
}

struct TicketMediaLabel: View {
    let mediaType: MediaType

    private static let font = Font.system(size: 11, weight: .heavy)
    private static let tracking: CGFloat = 1.6

    var body: some View {
        Text(mediaType.displayName.uppercased())
            .font(Self.font)
            .tracking(Self.tracking)
            .lineLimit(1)
    }
}

#Preview("Подписи на корешках") {
    HStack(spacing: 12) {
        ForEach(MediaType.allCases) { mediaType in
            let ink = TicketInk.stub(for: mediaType)
            TicketStubHeader(title: "Наугад", mediaType: mediaType)
                .foregroundStyle(ink.ink)
                .padding(12)
                .frame(width: 180)
                .background(ink.paper)
                .environment(\.ticketInk, ink)
        }
    }
    .padding()
    .background(Color.black)
}
