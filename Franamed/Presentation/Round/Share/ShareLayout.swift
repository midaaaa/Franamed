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

    @MainActor
    static var stubAspect: CGFloat {
        let edgeStyle = TicketEdgeStyle(hasScallops: UserDefaults.standard.bool(forKey: TicketEdgeStyle.storageKey))
        return ResultStubMetrics.height(edgeStyle: edgeStyle) / ResultStubMetrics.width
    }

    static func tallness(of size: CGSize) -> CGFloat {
        min(max((size.height / max(size.width, 1) - 1) / (16.0 / 9 - 1), 0), 1)
    }

    static func of(_ format: ShareFormat, in size: CGSize) -> ShareStubPlacement {
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

    func mixed(with other: ShareStubPlacement, by t: CGFloat) -> ShareStubPlacement {
        ShareStubPlacement(center: CGPoint(x: center.x + (other.center.x - center.x) * t,
                                           y: center.y + (other.center.y - center.y) * t),
                           width: width + (other.width - width) * t,
                           angle: angle + (other.angle - angle) * Double(t))
    }
}

struct ShareSheetLayout {
    private(set) var canvas: CGRect
    private(set) var stub: CGRect
    let angle: Angle

    private static let bottomInset: CGFloat = 12
    private static let sheetCornerRadius: CGFloat = 42
    private static let regularTopInset: CGFloat = 24
    static let cardCornerRadius = sheetCornerRadius - regularTopInset
    private static let stickerTopInset: CGFloat = 8
    private static let gap: CGFloat = 12
    private static let sideInset: CGFloat = 24

    @MainActor
    static func fittedHeight(width: CGFloat, panelHeight: CGFloat, format: ShareFormat) -> CGFloat {
        let card = format.canvas
        let cardHeight = (width - 2 * sideInset) * card.height / card.width
        return (topInset(for: format) + cardHeight + gap + panelHeight + bottomInset).rounded(.up)
    }

    static func panelTop(height: CGFloat, panelHeight: CGFloat) -> CGFloat {
        height - panelHeight - bottomInset
    }

    private static func topInset(for format: ShareFormat) -> CGFloat {
        format == .sticker ? stickerTopInset : regularTopInset
    }

    @MainActor
    init(size: CGSize, panelHeight: CGFloat, format: ShareFormat) {
        let top = Self.topInset(for: format)
        let bottom = Self.panelTop(height: size.height, panelHeight: panelHeight) - Self.gap
        let room = bottom - top
        let area = CGSize(width: size.width - 2 * Self.sideInset, height: max(room, 80))
        let card = format.canvas
        let scale = min(area.width / card.width, area.height / card.height)
        let fitted = CGSize(width: card.width * scale, height: card.height * scale)
        canvas = CGRect(x: (size.width - fitted.width) / 2, y: bottom - fitted.height,
                        width: fitted.width, height: fitted.height)
        let placement = ShareStubPlacement.of(format, in: card)
        let width = placement.width * scale
        let height = width * ShareStubPlacement.stubAspect
        stub = CGRect(x: canvas.minX + placement.center.x * scale - width / 2,
                      y: canvas.minY + placement.center.y * scale - height / 2,
                      width: width, height: height)
        angle = placement.angle
    }

    func offsetBy(dy: CGFloat) -> ShareSheetLayout {
        var layout = self
        layout.canvas = canvas.offsetBy(dx: 0, dy: dy)
        layout.stub = stub.offsetBy(dx: 0, dy: dy)
        return layout
    }
}
