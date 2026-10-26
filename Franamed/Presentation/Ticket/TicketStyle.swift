//
//  TicketStyle.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

enum TicketStyle {
    static let name = Font.system(size: 26, weight: .heavy)
    static let media = Font.system(size: 10, weight: .regular)
    static let fieldLabel = Font.system(size: 7.5, weight: .heavy)
    static let valueSize: CGFloat = 15
    static let valueUIFont = UIFont.systemFont(ofSize: valueSize, weight: .medium)
    static let codeCaption = Font.system(size: 8.5, weight: .heavy)
    static let serial = Font.system(size: 7, weight: .medium, design: .monospaced)

    static func value(isSet: Bool) -> Font {
        .system(size: valueSize, weight: isSet ? .semibold : .medium).monospacedDigit()
    }

    static let placeholderInk = Color.black.opacity(0.32)
    static let paper = Color(white: 0.9)

    static let mediaTracking: CGFloat = 0.6
    static let fieldLabelTracking: CGFloat = 1
    static let codeCaptionTracking: CGFloat = 2.4
    static let serialTracking: CGFloat = 1.6
    static let minimumScale: CGFloat = 0.7

    static let screenInset: CGFloat = 50
    static let maxWidth: CGFloat = 480
    static let verticalInset: CGFloat = 24
    static let referenceWidth: CGFloat = 293
    static let posterAspectRatio: CGFloat = 1.5
    static let tearNotchRadius: CGFloat = 16
    static let paperThickness: CGFloat = 1
    static let stubPadding: CGFloat = 12
    static let stubSpacing: CGFloat = 8
    static let stubSideInset: CGFloat = 16
    static let stubBodyHeight: CGFloat = 185
    static let stubBodyWidth = referenceWidth - stubSideInset * 2
    static let serialBand: CGFloat = 8
    static let ruleWidth: CGFloat = 1.2
    static let headerSpacing: CGFloat = 6
    static let fieldLeadingWidth: CGFloat = 62
    static let fieldTrailingWidth: CGFloat = 78
    static let codeHeight: CGFloat = 39
    static let codeGap: CGFloat = 7
}

extension TicketStyle {
    static func width(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(0, screenWidth - screenInset * 2))
    }

    static func cardWidth(in container: CGSize, edgeStyle: TicketEdgeStyle) -> CGFloat {
        let byWidth = width(forScreenWidth: container.width)
        let stubPerWidth = TicketStubMetrics.height(width: referenceWidth, edgeStyle: edgeStyle) / referenceWidth
        let byHeight = (container.height - verticalInset * 2) / (posterAspectRatio + stubPerWidth)
        return max(0, min(byWidth, byHeight))
    }

    static func zoom(forWidth width: CGFloat) -> CGFloat {
        width / referenceWidth
    }

    static func notchRadius(forWidth width: CGFloat) -> CGFloat {
        tearNotchRadius * zoom(forWidth: width)
    }
}
