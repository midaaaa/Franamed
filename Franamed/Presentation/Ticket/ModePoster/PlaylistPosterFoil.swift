//
//  PlaylistPosterFoil.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import SwiftUI

struct PlaylistPosterFoil: View {
    let image: UIImage
    let url: URL

    @ObservedObject private var motion = PosterTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterSwipeTurn) private var swipeTurn
    @State private var loaded: Loaded?

    private var content: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    var body: some View {
        let tilt = reduceMotion ? .zero : motion.phase + SIMD2(swipeTurn, 0)
        ZStack {
            content
            if let mask, let maskImage = mask.image {
                let shader = shader(tilt: tilt, mask: Image(uiImage: maskImage), mean: mask.mean)
                content
                    .visualEffect { view, proxy in
                        view.layerEffect(shader(proxy.size), maxSampleOffset: .zero)
                    }
                    .id(key)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: mask?.image != nil)
        .task(id: key) {
            let key = key
            var made = PosterMaskStore.shared.cachedMask(for: url)
            if made == nil { made = await PosterMaskStore.shared.mask(for: url, image: image) }
            guard let made else { return }
            loaded = Loaded(key: key, mask: made)
        }
        .posterTilt()
    }

    private var key: PosterKey { PosterKey(url: url, image: ObjectIdentifier(image)) }

    private var mask: PosterMask? {
        if let loaded, loaded.key == key { return loaded.mask }
        return PosterMaskStore.shared.memoryMask(for: url)
    }

    nonisolated static func prepare(url: URL, image: UIImage) async {
        _ = await PosterMaskStore.shared.mask(for: url, image: image)
    }

    private struct PosterKey: Hashable {
        let url: URL
        let image: ObjectIdentifier
    }

    private struct Loaded {
        let key: PosterKey
        let mask: PosterMask
    }

    private func shader(tilt: SIMD2<Float>, mask: Image, mean: Float) -> @Sendable (CGSize) -> Shader {
        let style = Float(PosterFinish.playlist.rawValue)
        return { size in
            ShaderLibrary.posterFoilMasked(.float2(size), .float2(tilt.x, tilt.y), .float(style), .float(mean),
                                           .image(mask))
        }
    }
}
