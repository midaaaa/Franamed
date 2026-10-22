//
//  PlaylistTicketGeometry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

enum PlaylistTicketGeometry {
    private static let referenceGap: CGFloat = 14
    private static let referenceRipSeparation: CGFloat = 6

    static func gap(width: CGFloat) -> CGFloat {
        referenceGap * TicketStyle.zoom(forWidth: width)
    }

    static func ripSeparation(width: CGFloat) -> CGFloat {
        referenceRipSeparation * TicketStyle.zoom(forWidth: width)
    }

    static func posterHeight(width: CGFloat) -> CGFloat {
        width * TicketStyle.posterAspectRatio
    }

    static func height(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGFloat {
        posterHeight(width: width) + TicketStubMetrics.height(width: width, edgeStyle: edgeStyle)
    }

    static func frameHeight(width: CGFloat, edgeStyle: TicketEdgeStyle) -> CGFloat {
        height(width: width, edgeStyle: edgeStyle) + gap(width: width)
    }

    static func aspectRatio(edgeStyle: TicketEdgeStyle) -> CGFloat {
        let width = TicketStyle.referenceWidth
        return width / frameHeight(width: width, edgeStyle: edgeStyle)
    }

    static func shape(width: CGFloat, edgeStyle: TicketEdgeStyle, isPerforated: Bool = true) -> TicketPerforationShape {
        TicketPerforationShape(tearLineOffset: posterHeight(width: width),
                               tearLineSlots: isPerforated
                                   ? TearPerforation(config: .ticket(width: width), length: width) : nil,
                               edgeStyle: edgeStyle,
                               designSize: CGSize(width: width, height: height(width: width, edgeStyle: edgeStyle)))
    }

    static func outline(width: CGFloat, edgeStyle: TicketEdgeStyle) -> some View {
        shape(width: width, edgeStyle: edgeStyle)
            .frame(width: width, height: height(width: width, edgeStyle: edgeStyle))
    }
}

enum PlaylistStubCut: Equatable {
    case attached
    case detached
    case ripped(seed: UInt64)
}

struct PlaylistTicketPoster: View {
    let display: PlaylistEntryDisplay
    let url: URL?
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle

    private static let questionSize: CGFloat = 160
    private static let pendingFill = Color(white: 0.24)
    private static let pendingInk = Color(white: 0.42)

    var body: some View {
        content
            .frame(width: width, height: PlaylistTicketGeometry.posterHeight(width: width))
            .clipped()
            .mask(alignment: .top) {
                PlaylistTicketGeometry.outline(width: width, edgeStyle: edgeStyle)
            }
    }

    @ViewBuilder
    private var content: some View {
        if display.isPlayed {
            CachedRemoteImage(url: url)
        } else {
            ZStack {
                Rectangle().fill(Self.pendingFill)
                Text("?")
                    .font(.custom("Georgia-Bold", fixedSize: Self.questionSize * TicketStyle.zoom(forWidth: width)))
                    .foregroundStyle(Self.pendingInk)
            }
        }
    }
}

struct PlaylistStubPiece<Paper: View>: View {
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle
    let cut: PlaylistStubCut
    @ViewBuilder let paper: Paper

    var body: some View {
        switch cut {
        case .attached:
            paper.mask(alignment: .bottom) {
                PlaylistTicketGeometry.outline(width: width, edgeStyle: edgeStyle)
            }
        case .detached:
            detached
        case .ripped(let seed):
            let separation = PlaylistTicketGeometry.ripSeparation(width: width)
            ZStack {
                detached.mask(PlaylistStubTearShape(seed: seed, side: .leading)).offset(x: -separation)
                detached.mask(PlaylistStubTearShape(seed: seed, side: .trailing)).offset(x: separation)
            }
        }
    }

    private var detached: some View {
        paper.clipShape(ResultStubShape(edgeStyle: edgeStyle))
    }
}

struct PlaylistStubTearShape: Shape {
    enum Side {
        case leading
        case trailing
    }

    let seed: UInt64
    let side: Side

    private static let samples = 96

    func path(in rect: CGRect) -> Path {
        let (line, shape) = FlipTear(seed: seed).shape(width: rect.width)
        let k = Float(TicketStyle.zoom(forWidth: rect.width))
        let height = Float(rect.height)
        let edge = side == .leading ? rect.minX - 1 : rect.maxX + 1
        var path = Path()
        path.move(to: CGPoint(x: edge, y: rect.minY))
        for index in 0...Self.samples {
            let y = (Float(index) / Float(Self.samples) - 0.5) * height
            let t = y / height + 0.5
            let x = line.x + (line.y - line.x) * t
                + shape.x * sin(6.2832 * 0.7 * t + line.z)
                + shape.y * sin(6.2832 * 2.1 * t + line.w)
                + 1.3 * k * Self.noise(y / (3.2 * k), seed: shape.z)
                + 0.5 * k * Self.noise(y / (1.1 * k), seed: shape.z + 3)
            path.addLine(to: CGPoint(x: rect.midX + CGFloat(x), y: rect.midY + CGFloat(y)))
        }
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private static func hash(_ n: Float) -> Float {
        let value = sin(n) * 43758.5453
        return value - floor(value)
    }

    private static func noise(_ x: Float, seed: Float) -> Float {
        let i = floor(x)
        let f = x - i
        let k = f * f * (3 - 2 * f)
        let a = hash(i + seed * 17.13)
        let b = hash(i + 1 + seed * 17.13)
        return (a + (b - a) * k) * 2 - 1
    }
}
