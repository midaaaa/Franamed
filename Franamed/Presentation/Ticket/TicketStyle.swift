//
//  TicketStyle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

enum TicketStyle {
    static let title = Font.system(size: 24, weight: .bold, design: .serif)
    static let fieldLabel = Font.system(size: 10, weight: .semibold)
    static let fieldValue = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let fieldPlaceholder = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let meta = Font.system(size: 13, weight: .medium)
    static let serial = Font.system(size: 10, weight: .medium, design: .monospaced)

    static let placeholderInk = Color.black.opacity(0.32)

    static let fieldLabelTracking: CGFloat = 1.1
    static let serialTracking: CGFloat = 1.5
    static let valueSymbolSize: CGFloat = 14
    static let minimumScale: CGFloat = 0.7

    static let screenInset: CGFloat = 50
    static let posterAspectRatio: CGFloat = 1.5
    static let tearNotchRadius: CGFloat = 16
    static let stubPadding: CGFloat = 12
    static let stubSpacing: CGFloat = 8
    static let fieldRowSpacing: CGFloat = 6
    static let fieldLabelSpacing: CGFloat = 0
    static let fieldColumnGap: CGFloat = 12
    static let symbolTextSpacing: CGFloat = 3
    static let metaSpacing: CGFloat = 6

    static let barcodeHeight: CGFloat = 36
    static let barcodeBarSpacing: CGFloat = 2
    static let barcodeBarScale: CGFloat = 1.5
    static let barcodeSerialSpacing: CGFloat = 5
}

