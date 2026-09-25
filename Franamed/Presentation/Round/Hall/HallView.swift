//
//  HallView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import SwiftUI

struct LiveHallView: View {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat

    @StateObject private var motion = HallMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HallView(sample: sample, scene: scene, size: size, frameTop: frameTop, frameBottom: frameBottom,
                 sway: motion.sway, scale: motion.isMoving ? HallView.movingScale : 1)
            .equatable()
            .onAppear { updateMotion() }
            .onDisappear { motion.stop() }
            .onChange(of: reduceMotion) { _, _ in updateMotion() }
    }

    private func updateMotion() {
        if reduceMotion { motion.stop() } else { motion.start() }
    }
}

struct HallView: View, Equatable {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat
    var sway: SIMD2<Float> = .zero
    var scale: CGFloat = 1

    static let movingScale: CGFloat = 0.65

    nonisolated static func == (lhs: HallView, rhs: HallView) -> Bool {
        lhs.sample == rhs.sample && lhs.scene == rhs.scene && lhs.size == rhs.size
            && lhs.frameTop == rhs.frameTop && lhs.frameBottom == rhs.frameBottom
            && lhs.sway == rhs.sway && lhs.scale == rhs.scale
    }

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: size.width * scale, height: size.height * scale)
            .colorEffect(shader(scale: scale))
            .scaleEffect(1 / scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func shader(scale: CGFloat) -> Shader {
        let camera = HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom)
        let eye = scene.eye + SIMD3(sway.x, sway.y, 0)
        let focal = Float(camera.focal)
        let centerX = Float(size.width / 2) + focal * sway.x / eye.z
        let principalY = Float(camera.principalY) - focal * sway.y / eye.z
        let s = Float(scale)

        return ShaderLibrary.cinemaHall(
            .float3(focal * s, principalY * s, centerX * s),
            .float4(eye.x, eye.y, eye.z, Float(scene.rowsInFront)),
            .float4(scene.rowPitch, scene.rowRise, HallScene.rowArc, scene.recline),
            .float3(scene.seatPitch, scene.backWidth, scene.seatTop),
            .float4(scene.armrestHeight, scene.armrestWidth, scene.armrestLength, scene.armrestSetback),
            .float3(HallScene.screenWidth, HallScene.screenHeight, HallScene.screenBottom),
            .float3(sample.mean.x, sample.mean.y, sample.mean.z),
            .floatArray(sample.blurredInterleaved)
        )
    }
}
