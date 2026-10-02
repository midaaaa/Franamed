//
//  HallView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import Combine
import SwiftUI

struct LiveHallView: View {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat

    @State private var motion = HallMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private static let redrawPixels: Float = 2
    private static let nearArmDepth: Float = 0.6

    var body: some View {
        HallMetalView(sample: sample, scene: scene, size: size, frameTop: frameTop, frameBottom: frameBottom,
                      motion: motion)
            .frame(width: size.width, height: size.height)
            .onAppear { updateMotion() }
            .onDisappear { motion.stop() }
            .onChange(of: reduceMotion) { _, _ in updateMotion() }
            .onReceive(Self.energyChanges) { _ in updateMotion() }
            .onChange(of: motionThreshold, initial: true) { _, threshold in motion.threshold = threshold }
    }

    private var motionThreshold: Float {
        let focal = Float(HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom).focal * displayScale)
        let pixelsPerMeter = focal * (1 / Self.nearArmDepth - 1 / scene.eye.z)
        return Self.redrawPixels / max(pixelsPerMeter, 1)
    }

    private func updateMotion() {
        if reduceMotion || Self.savesEnergy { motion.stop() } else { motion.start() }
    }

    private static var savesEnergy: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private static var energyChanges: AnyPublisher<Notification, Never> {
        let center = NotificationCenter.default
        return center.publisher(for: .NSProcessInfoPowerStateDidChange)
            .merge(with: center.publisher(for: ProcessInfo.thermalStateDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

struct HallView: View, Equatable {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat

    nonisolated static func == (lhs: HallView, rhs: HallView) -> Bool {
        lhs.sample == rhs.sample && lhs.scene == rhs.scene && lhs.size == rhs.size
            && lhs.frameTop == rhs.frameTop && lhs.frameBottom == rhs.frameBottom
    }

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .colorEffect(shader)
    }

    private var shader: Shader {
        let args = HallShaderArgs(scene: scene, sample: sample, size: size, frameTop: frameTop,
                                  frameBottom: frameBottom, sway: .zero, scale: 1)
        return ShaderLibrary.cinemaHall(
            .vector(args.camera), .vector(args.eyeRows), .vector(args.rowShape), .vector(args.seat),
            .vector(args.arm), .vector(args.screen), .vector(args.mean), .vector(args.options),
            .floatArray(sample.blurredInterleaved)
        )
    }
}

struct HallShaderArgs {
    var camera: SIMD4<Float>
    var eyeRows: SIMD4<Float>
    var rowShape: SIMD4<Float>
    var seat: SIMD4<Float>
    var arm: SIMD4<Float>
    var screen: SIMD4<Float>
    var mean: SIMD4<Float>
    var options: SIMD4<Float>

    static let rayFlags: Float = 7

    init(scene: HallScene, sample: HallFrameSample, size: CGSize, frameTop: CGFloat, frameBottom: CGFloat,
         sway: SIMD2<Float>, scale: CGFloat) {
        let camera = HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom)
        let eye = scene.eye + SIMD3(sway.x, sway.y, 0)
        let focal = Float(camera.focal)
        let centerX = Float(size.width / 2) + focal * sway.x / eye.z
        let principalY = Float(camera.principalY) - focal * sway.y / eye.z
        let s = Float(scale)

        self.camera = SIMD4(focal * s, principalY * s, centerX * s, 0)
        eyeRows = SIMD4(eye.x, eye.y, eye.z, Float(scene.rowsInFront))
        rowShape = SIMD4(scene.rowPitch, scene.rowRise, HallScene.rowArc, scene.recline)
        seat = SIMD4(scene.seatPitch, scene.backWidth, scene.seatTop, 0)
        arm = SIMD4(scene.armrestHeight, scene.armrestWidth, scene.armrestLength, scene.armrestSetback)
        screen = SIMD4(HallScene.screenWidth, HallScene.screenHeight, HallScene.screenBottom, 0)
        mean = SIMD4(sample.mean, 0)
        options = SIMD4(Self.rayFlags, Float(frameTop) * s, Float(frameBottom) * s, 0)
    }
}

private extension Shader.Argument {
    static func vector(_ value: SIMD4<Float>) -> Shader.Argument {
        .float4(value.x, value.y, value.z, value.w)
    }
}
