//
//  RoundBackground.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import SwiftUI

struct RoundBackground: View {
    let light: HallFrameSample
    let frameHeight: CGFloat
    let isProtected: Bool
    let showsCaptureBanner: Bool
    let coordinateSpace: String

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .named(coordinateSpace)).minY
            ZStack(alignment: .topLeading) {
                if isProtected {
                    captureLayer(size: proxy.size, origin: origin)
                }
                ProtectedContent(isProtected: isProtected) {
                    liveLayer(size: proxy.size, origin: origin)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func liveLayer(size: CGSize, origin: CGFloat) -> some View {
        LiveHallView(sample: light, scene: HallScene(), size: size,
                     frameTop: -origin, frameBottom: frameHeight - origin)
    }

    private func captureLayer(size: CGSize, origin: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HallView(sample: showsCaptureBanner ? CaptureWarningBanner.hallLight : light,
                     scene: HallScene(), size: size,
                     frameTop: -origin, frameBottom: frameHeight - origin)
                .equatable()
            if showsCaptureBanner {
                CaptureWarningBanner()
                    .frame(width: size.width, height: frameHeight)
                    .offset(y: -origin)
            }
        }
    }
}
