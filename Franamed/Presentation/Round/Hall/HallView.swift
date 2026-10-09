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
    var picture: HallPicture?
    var isWaiting = false
    var phone: HallPhone?

    @State private var motion = HallMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private static let redrawPixels: Float = 2
    private static let nearArmDepth: Float = 0.6

    var body: some View {
        HallMetalView(sample: sample, scene: scene, size: size, frameTop: frameTop, frameBottom: frameBottom,
                      picture: picture, isWaiting: isWaiting, motion: motion, phone: phone)
            .frame(width: size.width, height: size.height)
            .onAppear { updateMotion() }
            .onDisappear { motion.stop() }
            .onChange(of: reduceMotion) { _, _ in updateMotion() }
            .onReceive(Self.energyChanges) { _ in updateMotion() }
            .onChange(of: motionThreshold, initial: true) { _, threshold in motion.threshold = threshold }
            .onChange(of: phoneRest, initial: true) { _, rest in
                phone?.setRest(rest)
            }
    }

    private var motionThreshold: Float {
        let focal = Float(HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom).focal * displayScale)
        let pixelsPerMeter = focal * (1 / Self.nearArmDepth - 1 / scene.eye.z)
        return Self.redrawPixels / max(pixelsPerMeter, 1)
    }

    private var phoneRest: CGPoint {
        let camera = HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom)
        let eye = scene.eye
        let arm = HallPhoneDraw.armPoint(eye: eye, seatPitch: scene.seatPitch,
                                         armTop: scene.rowRise * Float(scene.rowsInFront) + scene.armrestHeight)
        let center = SIMD2(Float(size.width / 2), Float(camera.principalY))
        let rest = HallPhoneDraw.project(arm, eye: eye, focal: Float(camera.focal), center: center)
        return CGPoint(x: CGFloat(rest.x), y: CGFloat(rest.y))
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

struct HallShaderArgs {
    var camera: SIMD4<Float>
    var eye: SIMD4<Float>
    var rows: SIMD4<Float>
    var seat: SIMD4<Float>
    var arm: SIMD4<Float>
    var screen: SIMD4<Float>
    var mean: SIMD4<Float>
    var frame: SIMD4<Float>
    var picture: SIMD4<Float>
    var glow: SIMD4<Float> = .zero

    init(scene: HallScene, sample: HallFrameSample, size: CGSize, frameTop: CGFloat, frameBottom: CGFloat,
         sway: SIMD2<Float>, scale: CGFloat, picture: HallPicture? = nil, spinnerTime: Float? = nil) {
        let camera = HallCamera(scene: scene, frameTop: frameTop, frameBottom: frameBottom)
        let eye = scene.eye + SIMD3(sway.x, sway.y, 0)
        let focal = Float(camera.focal)
        let centerX = Float(size.width / 2) + focal * sway.x / eye.z
        let principalY = Float(camera.principalY) - focal * sway.y / eye.z
        let s = Float(scale)

        self.camera = SIMD4(focal * s, principalY * s, centerX * s, 0)
        self.eye = SIMD4(eye, 0)
        rows = SIMD4(Float(scene.rowsInFront), scene.rowRise, scene.recline, 0)
        seat = SIMD4(scene.seatPitch, scene.backWidth, scene.seatTop, 0)
        arm = SIMD4(scene.armrestHeight, scene.armrestLength, scene.armrestSetback, 0)
        screen = SIMD4(HallScene.screenWidth, HallScene.screenHeight, HallScene.screenBottom, 0)
        mean = SIMD4(sample.mean, 0)
        frame = SIMD4((Float(frameTop) * s).rounded(), (Float(frameBottom) * s).rounded(), 0,
                      (Float(size.width) * s).rounded())
        self.picture = SIMD4(picture?.aspect ?? 0, picture == nil ? 0 : 1, Float(size.width), spinnerTime ?? -1)
    }
}
