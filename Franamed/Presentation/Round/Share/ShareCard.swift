//
//  ShareCard.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import SwiftUI
import simd

struct ShareCard: View {
    let material: ShareMaterial
    let mode: ShareMode
    let background: ShareBackground
    let format: ShareFormat
    var showsStub = true
    var showsOverlays = true
    var cornerRadius: CGFloat = 0
    var height: CGFloat?
    var stickerness: CGFloat?

    private var size: CGSize { CGSize(width: format.canvas.width, height: height ?? format.canvas.height) }
    private var sticker: CGFloat { stickerness ?? (format == .sticker ? 1 : 0) }
    private var tallness: CGFloat { ShareStubPlacement.tallness(of: size) }

    private var placement: ShareStubPlacement {
        ShareStubPlacement.of(.story, in: size).mixed(with: .of(.sticker, in: size), by: sticker)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                backdrop
                    .frame(width: size.width, height: size.height)
                if background == .hall {
                    hallPicture
                }
                if showsOverlays {
                    overlays
                        .frame(width: size.width, height: size.height)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .opacity(Double(1 - sticker))
            if showsStub {
                ForEach(ShareMode.allCases, id: \.self) { layer in
                    let content = layer.stub(of: material.content)
                    ShareStub(content: content, image: material.stubs[content]?.shadowed)
                        .modifier(ShareStubPose(placement: placement))
                        .opacity(layer == mode ? 1 : 0)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        switch background {
        case .hall:
            hall
        case .poster:
            filled(material.poster)
        case .black:
            Color.black
        }
    }

    private func filled(_ image: UIImage?) -> some View {
        Color.black.overlay {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
    }

    private var hall: some View {
        let rect = material.hallRect
        return ZStack(alignment: .topLeading) {
            Color.black
            ForEach(ShareMode.allCases, id: \.self) { layer in
                if let image = material.halls[layer] {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .opacity(layer == mode ? 1 : 0)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private var hallPicture: some View {
        let frame = ShareMaterial.cardFrame
        return ForEach(ShareMode.allCases, id: \.self) { layer in
            if let picture = material.picture(for: layer) {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(layer == mode ? 1 : 0)
            }
        }
    }

    // MARK: Overlays

    private static let riddleScrimDepth: CGFloat = 90

    private var riddleScrim: Double {
        let luminance: Float = switch background {
        case .hall: simd_dot(material.firstLight.mean, SIMD3(0.2126, 0.7152, 0.0722))
        case .poster: Float(SharePosterBackdrop.targetLuminance)
        case .black: 0
        }
        return min(0.45, Double(luminance) * 0.9)
    }

    private var edgeInset: CGFloat { size.height * (0.05 + 0.08 * tallness) }

    private var overlays: some View {
        ZStack {
            if mode == .riddle {
                LinearGradient(stops: [.init(color: .black.opacity(riddleScrim), location: 0),
                                       .init(color: .black.opacity(riddleScrim * 0.8), location: 0.6),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: edgeInset + Self.riddleScrimDepth)
                    .frame(maxHeight: .infinity, alignment: .top)
                VStack(spacing: 8) {
                    Text(material.challengeTitle)
                        .font(.system(size: 26 + 4 * tallness, weight: .bold))
                    Text(material.challengeLine)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, edgeInset)
            }
            Text("FRANAMED")
                .font(.system(size: 13, weight: .bold))
                .tracking(5)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, edgeInset)
        }
    }

    // MARK: Export

    @MainActor
    func image(scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, .dark))
        renderer.scale = scale
        renderer.isOpaque = format != .sticker
        return renderer.uiImage
    }
}

#Preview("Карточка — загадка, зал") {
    ShareCard(material: .preview, mode: .riddle, background: .hall, format: .story)
}

#Preview("Карточка — пост, чёрный, ответ") {
    ShareCard(material: .preview, mode: .answer, background: .black, format: .square)
}

#Preview("Карточка — корешок") {
    ShareCard(material: .preview, mode: .answer, background: .black, format: .sticker)
}
