//
//  ShareLayout.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import SwiftUI

struct ShareStubPlacement {
    let center: CGPoint
    let width: CGFloat
    let angle: Angle

    static let stickerShare: CGFloat = 0.92

    static var stubAspect: CGFloat {
        let width = TicketStyle.referenceWidth
        return TicketStubMetrics.height(width: width, edgeStyle: .stored) / width
    }

    static func tallness(of size: CGSize) -> CGFloat {
        min(max((size.height / max(size.width, 1) - 1) / (16.0 / 9 - 1), 0), 1)
    }

    private static func of(_ format: ShareFormat, in size: CGSize) -> ShareStubPlacement {
        switch format {
        case .story, .square:
            let tallness = tallness(of: size)
            return ShareStubPlacement(center: CGPoint(x: size.width / 2, y: size.height * (0.5 + 0.02 * tallness)),
                                      width: size.width * (0.66 + 0.12 * tallness), angle: .degrees(-2))
        case .sticker:
            return ShareStubPlacement(center: CGPoint(x: size.width / 2, y: size.height / 2),
                                      width: size.width * stickerShare, angle: .zero)
        }
    }

    static func of(stickerness: CGFloat, in size: CGSize) -> ShareStubPlacement {
        of(.story, in: size).mixed(with: of(.sticker, in: size), by: stickerness)
    }

    private func mixed(with other: ShareStubPlacement, by t: CGFloat) -> ShareStubPlacement {
        ShareStubPlacement(center: CGPoint(x: center.x + (other.center.x - center.x) * t,
                                           y: center.y + (other.center.y - center.y) * t),
                           width: width + (other.width - width) * t,
                           angle: angle + (other.angle - angle) * Double(t))
    }
}

struct ShareCardShape: Equatable {
    var lift: CGFloat
    var aspect: CGFloat
    var inset: CGFloat
    var stickerness: CGFloat

    @MainActor
    init(format: ShareFormat, panelHeight: CGFloat) {
        lift = ShareSheetLayout.cardLift(panelHeight: panelHeight)
        aspect = format.aspect
        inset = ShareSheetLayout.topInset(for: format)
        stickerness = format == .sticker ? 1 : 0
    }

    func mixed(with other: ShareCardShape, by t: CGFloat) -> ShareCardShape {
        var shape = self
        shape.lift += (other.lift - lift) * t
        shape.aspect += (other.aspect - aspect) * t
        shape.inset += (other.inset - inset) * t
        shape.stickerness += (other.stickerness - stickerness) * t
        return shape
    }
}

struct ShareSheetLayout {
    private(set) var canvas: CGRect
    private(set) var stub: CGRect
    let angle: Angle

    static let coordinateSpace = "shareSheet"
    private static let bottomInset: CGFloat = 12
    private static let sheetCornerRadius: CGFloat = 42
    private static let regularTopInset: CGFloat = 24
    static let cardCornerRadius = sheetCornerRadius - regularTopInset
    private static let stickerTopInset: CGFloat = 8
    private static let gap: CGFloat = 12
    private static let sideInset: CGFloat = 24
    private static let regularStubShare: CGFloat = 0.8

    @MainActor
    static func fittedHeight(width: CGFloat, panelHeight: CGFloat, format: ShareFormat, stubWidth: CGFloat) -> CGFloat {
        let card = format.canvas
        let cardWidth = widthLimit(width: width, stubWidth: stubWidth, stickerness: format == .sticker ? 1 : 0)
        let cardHeight = cardWidth * card.height / card.width
        return (topInset(for: format) + cardHeight + gap + panelHeight + bottomInset).rounded(.up)
    }

    static func panelTop(height: CGFloat, panelHeight: CGFloat) -> CGFloat {
        height - panelHeight - bottomInset
    }

    static func cardLift(panelHeight: CGFloat) -> CGFloat {
        panelHeight + bottomInset + gap
    }

    static func topInset(for format: ShareFormat) -> CGFloat {
        format == .sticker ? stickerTopInset : regularTopInset
    }

    private static func widthLimit(width: CGFloat, stubWidth: CGFloat, stickerness: CGFloat) -> CGFloat {
        let full = width - 2 * sideInset
        let regular = min(full, stubWidth / regularStubShare)
        let sticker = min(full, stubWidth / ShareStubPlacement.stickerShare)
        return regular + (sticker - regular) * stickerness
    }

    private static func canvas(width: CGFloat, top: CGFloat, bottom: CGFloat, aspect: CGFloat,
                               limit: CGFloat) -> CGRect {
        let height = max(bottom - top, 80)
        let cardWidth = min(width - 2 * sideInset, height / aspect, limit)
        return CGRect(x: (width - cardWidth) / 2, y: bottom - height, width: cardWidth, height: height)
    }

    @MainActor
    init(size: CGSize, shape: ShareCardShape, stubWidth: CGFloat) {
        let limit = Self.widthLimit(width: size.width, stubWidth: stubWidth, stickerness: shape.stickerness)
        canvas = Self.canvas(width: size.width, top: shape.inset, bottom: size.height - shape.lift,
                             aspect: shape.aspect, limit: limit)
        let scale = canvas.width / ShareFormat.baseWidth
        let placement = ShareStubPlacement.of(stickerness: shape.stickerness,
                                              in: CGSize(width: ShareFormat.baseWidth, height: canvas.height / scale))
        let width = placement.width * scale
        let height = width * ShareStubPlacement.stubAspect
        stub = CGRect(x: canvas.minX + placement.center.x * scale - width / 2,
                      y: canvas.minY + placement.center.y * scale - height / 2,
                      width: width, height: height)
        angle = placement.angle
    }

    func offsetBy(dx: CGFloat = 0, dy: CGFloat) -> ShareSheetLayout {
        var layout = self
        layout.canvas = canvas.offsetBy(dx: dx, dy: dy)
        layout.stub = stub.offsetBy(dx: dx, dy: dy)
        return layout
    }
}
