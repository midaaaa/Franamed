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
    let picture: HallPicture?
    let isWaiting: Bool
    let phone: HallPhone
    let isProtected: Bool
    let showsCaptureBanner: Bool
    let coordinateSpace: String

    @Environment(\.displayScale) private var displayScale
    @AppStorage(DebugSettings.phoneAimKey) private var phoneAim = Double(HallPhone.Settings().aim)
    @AppStorage(DebugSettings.phoneWidthKey) private var phoneWidth = Double(HallPhone.Settings().width)
    @AppStorage(DebugSettings.phonePortraitKey) private var isPhonePortrait = false
    @AppStorage(DebugSettings.phoneSlowFinderKey) private var slowFinder = true
    @AppStorage(DebugSettings.phoneBloomKey) private var phoneBloom = 0.0
    @AppStorage(DebugSettings.screenBloomKey) private var screenBloom = 0.0
    @AppStorage(DebugSettings.phoneGridKey) private var showsGrid = false
    @AppStorage(DebugSettings.phoneWideKey) private var isWide = false
    @AppStorage(DebugSettings.phoneColorKey) private var color = HallPhoneColor.custom
    @State private var backdrop: (key: BackdropKey, image: UIImage)?

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
        .onChange(of: phoneSettings, initial: true) { _, settings in phone.settings = settings }
        .task {
            for isTurned in [!isPhonePortrait, isPhonePortrait] {
                for isWide in [false, true] {
                    for scale in HallPhone.Settings.zoomStops {
                        let key = HallPhoneChrome.Key(isWide: isWide, scale: scale, isTurned: isTurned)
                        if let picture = await HallPhoneChrome.picture(for: key) { phone.setChrome(picture, for: key) }
                    }
                }
            }
        }
    }

    private var phoneSettings: HallPhone.Settings {
        HallPhone.Settings(aim: Float(phoneAim), width: Float(phoneWidth),
                           isPortrait: isPhonePortrait, showsGrid: showsGrid,
                           isWide: isWide, color: HallPhoneColor.vector(color),
                           slowFinder: slowFinder, bloom: Float(phoneBloom),
                           screenBloom: Float(screenBloom))
    }

    private func liveLayer(size: CGSize, origin: CGFloat) -> some View {
        LiveHallView(sample: light, scene: HallScene(), size: size,
                     frameTop: -origin, frameBottom: frameHeight - origin, picture: picture,
                     isWaiting: isWaiting, phone: phone)
    }

    private func captureLayer(size: CGSize, origin: CGFloat) -> some View {
        let key = BackdropKey(size: size, origin: origin, frameHeight: frameHeight,
                              light: showsCaptureBanner ? nil : light)
        return Group {
            if let backdrop, backdrop.key == key {
                Image(uiImage: backdrop.image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                Color.black
            }
        }
        .task(id: key) { await renderBackdrop(key) }
    }

    private func renderBackdrop(_ key: BackdropKey) async {
        guard backdrop?.key != key,
              let hall = await HallSnapshot.image(sample: key.light ?? CaptureWarningBanner.hallLight,
                                                  scene: HallScene(), size: key.size, frameTop: -key.origin,
                                                  frameBottom: frameHeight - key.origin, scale: displayScale)
        else { return }
        let renderer = ImageRenderer(content: backdropContent(hall: hall, size: key.size, origin: key.origin))
        renderer.scale = displayScale
        if let image = renderer.uiImage { backdrop = (key, image) }
    }

    private func backdropContent(hall: UIImage, size: CGSize, origin: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: hall)
                .resizable()
                .frame(width: size.width, height: size.height)
            if showsCaptureBanner {
                CaptureWarningBanner()
                    .frame(width: size.width, height: frameHeight)
                    .offset(y: -origin)
            }
        }
    }
}

private struct BackdropKey: Equatable {
    let size: CGSize
    let origin: CGFloat
    let frameHeight: CGFloat
    let light: HallFrameSample?
}
