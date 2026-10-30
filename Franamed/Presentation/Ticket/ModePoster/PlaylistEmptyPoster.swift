//
//  PlaylistEmptyPoster.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 28.10.2026.
//

import SwiftUI

struct PlaylistEmptyPoster: View {
    let posters: [URL]
    let mediaType: MediaType

    @ObservedObject private var motion = PosterTilt.shared
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterSwipeTurn) private var swipeTurn

    private enum Metrics {
        static let count = 3
        static let ticketWidth: CGFloat = 0.4
        static let step = CGSize(width: 0.1, height: -0.06)
    }

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }

    private var slots: [URL?] {
        (0..<Metrics.count).map { $0 < posters.count ? posters[$0] : nil }
    }

    var body: some View {
        GeometryReader { geo in
            let tilt = reduceMotion ? .zero : motion.phase + SIMD2(swipeTurn, 0)
            ZStack {
                background(size: geo.size, tilt: tilt)
                stack(size: geo.size, tilt: tilt)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .posterTilt()
    }

    private func background(size: CGSize, tilt: SIMD2<Float>) -> some View {
        ZStack {
            TicketInk.print.paper
            QuestionMarkPattern(width: size.width)
                .layerEffect(
                    ShaderLibrary.posterFoil(.float2(size), .float2(tilt.x, tilt.y),
                                             .float(Float(PosterFinish.forMode(.collection).rawValue))),
                    maxSampleOffset: .zero
                )
        }
    }

    private func stack(size: CGSize, tilt: SIMD2<Float>) -> some View {
        let width = size.width
        let ticketWidth = width * Metrics.ticketWidth
        let ticketHeight = PlaylistTicketGeometry.height(width: ticketWidth, edgeStyle: edgeStyle)
        return ZStack {
            ForEach(Array(slots.enumerated()).reversed(), id: \.offset) { index, url in
                let shift = CGFloat(index) - 1
                let offset = CGSize(width: width * Metrics.step.width * shift, height: width * Metrics.step.height * shift)
                let origin = CGPoint(x: (size.width - ticketWidth) / 2 + offset.width,
                                     y: (size.height - ticketHeight) / 2 + offset.height)
                PlaylistMiniTicket(url: url, showsNumber: index == 0, width: ticketWidth, edgeStyle: edgeStyle,
                                   tilt: tilt, posterSize: size, origin: origin, ink: .stub(for: mediaType))
                    .offset(offset)
            }
        }
        .compositingGroup()
    }
}

struct PlaylistMiniTicket: View {
    let url: URL?
    let showsNumber: Bool
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle
    let tilt: SIMD2<Float>
    let posterSize: CGSize
    let origin: CGPoint
    let ink: TicketInk

    private static let bevelRadius: CGFloat = 1.5
    private static let bevelDepth: CGFloat = 1.6
    private static let bevelStrength: CGFloat = 0.9
    private static let perforationRadius: CGFloat = 0.8
    private static let perforationDepth: CGFloat = 1
    private static let perforationStrength: CGFloat = 0.6

    var body: some View {
        let reference = TicketStyle.referenceWidth
        let outline = PlaylistTicketGeometry.shape(width: width, edgeStyle: edgeStyle, isPerforated: false)
        let size = CGSize(width: width, height: PlaylistTicketGeometry.height(width: width, edgeStyle: edgeStyle))
        VStack(spacing: 0) {
            PlaylistTicketPoster(display: .guessed(frame: 1), url: url, width: reference, edgeStyle: edgeStyle)
            PlaylistStubPiece(width: reference, edgeStyle: edgeStyle, cut: .attached) {
                ZStack {
                    if showsNumber { PlaylistTicketNumber(number: 1, display: .guessed(frame: 1)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(TicketStubFrame(width: reference, edgeStyle: edgeStyle))
                .background(ink.paper)
                .environment(\.ticketInk, ink)
            }
        }
        .frame(width: reference, height: PlaylistTicketGeometry.height(width: reference, edgeStyle: edgeStyle))
        .scaleEffect(width / reference, anchor: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay {
            PosterBevel(shape: outline, id: "ticketOutline-\(edgeStyle)", size: size,
                        radius: Self.bevelRadius, depth: Self.bevelDepth, strength: Self.bevelStrength,
                        tilt: tilt, posterSize: posterSize, origin: origin)
        }
        .overlay {
            PosterBevel(shape: perforated, id: "ticketPerforated-\(edgeStyle)", size: size,
                        radius: Self.perforationRadius, depth: Self.perforationDepth,
                        strength: Self.perforationStrength, tilt: tilt, posterSize: posterSize, origin: origin)
                .mask { perforationStrip }
        }
    }

    private var perforated: TicketPerforationShape {
        PlaylistTicketGeometry.shape(width: width, edgeStyle: edgeStyle)
    }

    private var perforationStrip: some View {
        let inset = TicketStyle.notchRadius(forWidth: width)
        let depth = TicketTearConfig.ticket(width: width).holeHalfWidth
        let margin = Self.perforationRadius + 0.5
        return Rectangle()
            .frame(width: max(width - inset * 2, 0), height: depth + margin * 2)
            .position(x: width / 2, y: PlaylistTicketGeometry.posterHeight(width: width) + depth / 2)
    }
}

struct QuestionMarkPattern: View {
    let width: CGFloat

    private static let ink = Color(white: 0.22)
    private static let glyphHeight: CGFloat = 0.085
    private static let spacing = CGSize(width: 0.12, height: 0.13)

    var body: some View {
        Canvas { context, size in
            let glyphHeight = width * Self.glyphHeight
            let glyphWidth = glyphHeight * QuestionMarkShape.aspectRatio
            let step = CGSize(width: width * Self.spacing.width, height: width * Self.spacing.height)
            let rows = Int(size.height / step.height) + 2
            let columns = Int(size.width / step.width) + 2
            for row in 0..<rows {
                let shift = row.isMultiple(of: 2) ? 0 : step.width / 2
                for column in -1..<columns {
                    let center = CGPoint(x: CGFloat(column) * step.width + shift, y: CGFloat(row) * step.height)
                    let rect = CGRect(x: center.x - glyphWidth / 2, y: center.y - glyphHeight / 2,
                                      width: glyphWidth, height: glyphHeight)
                    context.fill(QuestionMarkShape().path(in: rect), with: .color(Self.ink))
                }
            }
        }
    }
}

#Preview("Пустая подборка") {
    PlaylistEmptyPoster(posters: [], mediaType: .tv)
        .frame(width: 293, height: 440)
        .clipShape(.rect(cornerRadius: 12))
        .padding()
        .background(.black)
}
