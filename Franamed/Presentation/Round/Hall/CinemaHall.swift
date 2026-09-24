//
//  CinemaHall.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import SwiftUI

struct CinemaHall: View, Equatable {
    let imageURL: URL?
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat

    @StateObject private var motion = HallMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let movingScale: CGFloat = 0.65

    nonisolated static func == (lhs: CinemaHall, rhs: CinemaHall) -> Bool {
        lhs.imageURL == rhs.imageURL && lhs.scene == rhs.scene && lhs.size == rhs.size
            && lhs.frameTop == rhs.frameTop && lhs.frameBottom == rhs.frameBottom
    }

    var body: some View {
        let scale = motion.isMoving ? Self.movingScale : 1

        Rectangle()
            .fill(.black)
            .frame(width: size.width * scale, height: size.height * scale)
            .colorEffect(shader(scale: scale))
            .scaleEffect(1 / scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onAppear { updateMotion() }
            .onDisappear { motion.stop() }
            .onChange(of: reduceMotion) { _, _ in updateMotion() }
    }

    private func updateMotion() {
        if reduceMotion { motion.stop() } else { motion.start() }
    }

    private func shader(scale: CGFloat) -> Shader {
        let camera = HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom)
        let sample = imageURL.flatMap(HallFrameSampleCache.sample(for:)) ?? .dark
        let sway = motion.sway
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
