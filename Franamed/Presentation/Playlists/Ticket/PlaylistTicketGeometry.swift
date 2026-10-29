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
    case detached(seed: UInt64, scar: Float)
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
        case .detached(let seed, let scar):
            detached(seed: seed).overlay {
                if scar > 0 { PlaylistStubScar(seed: seed, reach: scar) }
            }
        case .ripped(let seed):
            let separation = PlaylistTicketGeometry.ripSeparation(width: width)
            ZStack {
                detached(seed: seed).mask(PlaylistStubTearShape(seed: seed, side: .leading)).offset(x: -separation)
                detached(seed: seed).mask(PlaylistStubTearShape(seed: seed, side: .trailing)).offset(x: separation)
            }
        }
    }

    private func detached(seed: UInt64) -> some View {
        paper.clipShape(ResultStubShape(edgeStyle: edgeStyle, edge: TearEdge(seed: seed)))
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
        let line = PlaylistTearLine(seed: seed, rect: rect)
        let edge = side == .leading ? rect.minX - 1 : rect.maxX + 1
        var path = Path()
        path.move(to: CGPoint(x: edge, y: rect.minY))
        for index in 0...Self.samples {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(Self.samples)
            path.addLine(to: CGPoint(x: line.x(at: y), y: y))
        }
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PlaylistStubScar: View {
    let seed: UInt64
    let reach: Float

    private static let creaseWidth: CGFloat = 1.8
    private static let creaseInk = Color.black.opacity(0.22)
    private static let liftWidth: CGFloat = 1.4
    private static let liftOffset: CGFloat = 1.3
    private static let liftInk = Color.white.opacity(0.5)
    private static let printCreaseInk = Color.black.opacity(0.45)
    private static let fadeLength: CGFloat = 10

    @Environment(\.ticketInk) private var ink

    private var lift: Color {
        guard ink.isPrint else { return Self.liftInk }
        return Color(red: Double(ink.core.x), green: Double(ink.core.y), blue: Double(ink.core.z))
    }

    var body: some View {
        GeometryReader { proxy in
            let k = TicketStyle.zoom(forWidth: proxy.size.width)
            let shape = PlaylistStubScarShape(seed: seed, reach: CGFloat(reach))
            let end = CGFloat(reach)
            let fade = min(Self.fadeLength * k / max(proxy.size.height, 1), end)
            ZStack {
                shape.stroke(lift, style: StrokeStyle(lineWidth: Self.liftWidth * k, lineJoin: .round))
                    .offset(x: Self.liftOffset * k)
                shape.stroke(ink.isPrint ? Self.printCreaseInk : Self.creaseInk, style: StrokeStyle(lineWidth: Self.creaseWidth * k, lineJoin: .round))
            }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: end - fade),
                                       .init(color: .clear, location: end)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PlaylistStubScarShape: Shape {
    let seed: UInt64
    let reach: CGFloat

    private static let samples = 48

    func path(in rect: CGRect) -> Path {
        let line = PlaylistTearLine(seed: seed, rect: rect)
        let end = rect.minY + rect.height * reach
        var path = Path()
        for index in 0...Self.samples {
            let y = rect.minY + (end - rect.minY) * CGFloat(index) / CGFloat(Self.samples)
            let point = CGPoint(x: line.x(at: y), y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct PlaylistTearLine {
    private let line: SIMD4<Float>
    private let shape: SIMD4<Float>
    private let k: Float
    private let rect: CGRect

    init(seed: UInt64, rect: CGRect) {
        (line, shape) = FlipTear(seed: seed).shape(width: rect.width)
        k = Float(TicketStyle.zoom(forWidth: rect.width))
        self.rect = rect
    }

    func x(at y: CGFloat) -> CGFloat {
        let height = Float(rect.height)
        let local = Float(y - rect.midY)
        let t = local / height + 0.5
        let x = line.x + (line.y - line.x) * t
            + shape.x * sin(6.2832 * 0.7 * t + line.z)
            + shape.y * sin(6.2832 * 2.1 * t + line.w)
            + 1.3 * k * Self.noise(local / (3.2 * k), seed: shape.z)
            + 0.5 * k * Self.noise(local / (1.1 * k), seed: shape.z + 3)
        return rect.midX + CGFloat(x)
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
