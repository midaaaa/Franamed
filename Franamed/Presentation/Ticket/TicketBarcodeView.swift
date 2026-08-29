//
//  TicketBarcodeView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

struct TicketBarcodeView: View {
    let mediaType: MediaType
    let mode: TicketGameMode

    var body: some View {
        VStack(spacing: TicketStyle.barcodeSerialSpacing) {
            bars
            Text(serial)
                .font(TicketStyle.serial)
                .tracking(TicketStyle.serialTracking)
        }
        .foregroundStyle(Color.black)
    }

    private var bars: some View {
        HStack(spacing: TicketStyle.barcodeBarSpacing) {
            ForEach(Self.barWidths.indices, id: \.self) { index in
                Rectangle()
                    .fill(.black)
                    .frame(width: Self.barWidths[index] * TicketStyle.barcodeBarScale)
            }
        }
        .frame(height: TicketStyle.barcodeHeight)
        .clipped()
    }

    private var serial: String {
        let typeCode = mediaType == .movie ? "MV" : "TV"
        let number = 4200 + mode.rawValue * 137 + (mediaType == .movie ? 0 : 61)
        return "FRN \(typeCode) \(mode.serialCode) \(number)"
    }

    private static let barWidths: [CGFloat] = [
        3, 1, 2, 1, 4, 2, 1, 3, 1, 1, 2, 4, 1, 3, 2,
        1, 1, 4, 2, 3, 1, 2, 1, 4, 1, 1, 3, 2, 1, 4,
        2, 5, 1, 2, 1, 1, 3,
    ]
}

#Preview("Все режимы") {
    VStack(spacing: 16) {
        ForEach(MediaType.allCases, id: \.self) { mediaType in
            ForEach(TicketGameMode.allCases, id: \.self) { mode in
                TicketBarcodeView(mediaType: mediaType, mode: mode)
            }
        }
    }
    .padding()
    .background(Color.white)
}
