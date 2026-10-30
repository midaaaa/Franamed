//
//  ModePosterView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import SwiftUI

struct ModePosterView: View {
    let mode: TicketGameMode

    @ObservedObject private var motion = PosterTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterSwipeTurn) private var swipeTurn

    private static let bevelRadius: CGFloat = 3
    private static let bevelDepth: CGFloat = 2
    private static let bevelStrength: CGFloat = 0.9

    var body: some View {
        GeometryReader { proxy in
            let tilt = reduceMotion ? .zero : motion.phase + SIMD2(swipeTurn, 0)
            ZStack {
                background(size: proxy.size, tilt: tilt)
                glyph(size: proxy.size, tilt: tilt)
            }
        }
        .posterTilt()
    }

    private var style: Style { mode == .curated ? .seance : .random }

    // MARK: Background

    private func background(size: CGSize, tilt: SIMD2<Float>) -> some View {
        ZStack {
            LinearGradient(colors: style.colors, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.black.opacity(0), .black.opacity(style.vignette)],
                           center: UnitPoint(x: 0.5, y: 0.45),
                           startRadius: size.height * 0.3, endRadius: size.height * 0.75)
        }
        .frame(width: size.width, height: size.height)
        .layerEffect(
            ShaderLibrary.posterFoil(.float2(size), .float2(tilt.x, tilt.y),
                                     .float(Float(PosterFinish.forMode(mode).rawValue))),
            maxSampleOffset: .zero
        )
    }

    // MARK: Glyph

    static func glyphLayout(in size: CGSize) -> (size: CGSize, center: CGPoint) {
        let height = size.height * 0.49
        let width = height * QuestionMarkShape.aspectRatio
        return (CGSize(width: width, height: height),
                CGPoint(x: size.width / 2 + width * QuestionMarkShape.opticalShift, y: size.height * 0.489))
    }

    private func glyph(size: CGSize, tilt: SIMD2<Float>) -> some View {
        let (glyphSize, center) = Self.glyphLayout(in: size)
        let glyph = QuestionMarkShape()

        return ZStack {
            glyph
                .fill(LinearGradient(colors: [.white, Color(red: 0.93, green: 0.92, blue: 0.97)],
                                     startPoint: .top, endPoint: .bottom))
            PosterBevel(shape: glyph, id: "glyph", size: glyphSize, radius: Self.bevelRadius, depth: Self.bevelDepth,
                        strength: Self.bevelStrength, tilt: tilt, posterSize: size,
                        origin: CGPoint(x: center.x - glyphSize.width / 2, y: center.y - glyphSize.height / 2))
        }
        .frame(width: glyphSize.width, height: glyphSize.height)
        .position(center)
    }
}

private struct Style {
    let colors: [Color]
    let vignette: Double

    static let random = Style(
        colors: [Color(red: 0.21, green: 0.21, blue: 0.25), Color(red: 0.09, green: 0.09, blue: 0.11)],
        vignette: 0.2
    )

    static let seance = Style(
        colors: [Color(red: 0.29, green: 0.24, blue: 0.70), Color(red: 0.71, green: 0.25, blue: 0.65)],
        vignette: 0
    )
}

#Preview("Сеанс") {
    ModePosterView(mode: .curated)
        .frame(width: 293, height: 440)
        .clipShape(.rect(cornerRadius: 12))
        .padding()
        .background(.black)
}

#Preview("Наугад") {
    ModePosterView(mode: .random)
        .frame(width: 293, height: 440)
        .clipShape(.rect(cornerRadius: 12))
        .padding()
        .background(.black)
}
