//
//  HallMetalView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 01.10.2026.
//

import SwiftUI
import UIKit

struct HallMetalView: UIViewRepresentable {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat
    let picture: HallPicture?
    let isWaiting: Bool
    let motion: HallMotion
    let phone: HallPhone?

    func makeUIView(context: Context) -> HallLayerView {
        HallLayerView()
    }

    func updateUIView(_ view: HallLayerView, context: Context) {
        view.motion = motion
        view.phone = phone
        view.key = HallLayerView.Key(sample: sample, scene: scene, size: size, frameTop: frameTop,
                                     frameBottom: frameBottom, picture: picture,
                                     isWaiting: isWaiting)
    }

    static func dismantleUIView(_ view: HallLayerView, coordinator: ()) {
        view.motion = nil
        view.phone = nil
    }
}

final class HallLayerView: UIView {
    struct Key: Equatable {
        let sample: HallFrameSample
        let scene: HallScene
        let size: CGSize
        let frameTop: CGFloat
        let frameBottom: CGFloat
        let picture: HallPicture?
        let isWaiting: Bool
    }

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var key: Key? {
        didSet { if key != oldValue { render() } }
    }

    weak var motion: HallMotion? {
        didSet {
            guard motion !== oldValue else { return }
            oldValue?.onSway = nil
            motion?.onSway = { [weak self] _ in self?.requestFrame() }
            render()
        }
    }

    weak var phone: HallPhone? {
        didSet {
            guard phone !== oldValue else { return }
            oldValue?.onChange = nil
            phone?.onChange = { [weak self] in self?.requestFrame() }
            render()
        }
    }

    private struct Prepared: @unchecked Sendable {
        let key: Key
        let meshes: HallMeshSet
        let pixelScale: CGFloat
        let origin: CGPoint
        let screen: CGSize
        let corner: CGFloat
        let motion: HallMotion?
        let phone: HallPhone?
    }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private let lock = NSLock()
    nonisolated(unsafe) private var prepared: Prepared?
    nonisolated(unsafe) private var clock: HallFrameClock?
    nonisolated(unsafe) private var lastFinder: (time: CFTimeInterval, draw: HallPhoneDraw)?

    private static let slowFinderInterval: CFTimeInterval = 1.0 / 30 - 0.002
    private static let fallbackCorner: CGFloat = 55

    private let displayProbe = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        metalLayer.device = HallRenderer.shared?.device
        metalLayer.pixelFormat = .bgra8Unorm
        displayProbe.isHidden = true
        displayProbe.cornerConfiguration = .corners(radius: .containerConcentric())
        addSubview(displayProbe)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let clock = window == nil ? nil : HallFrameClock(layer: metalLayer) { [weak self] drawable, time in
            self?.drawFrame(to: drawable, at: time) ?? false
        }
        let old = lock.withLock {
            let old = self.clock
            self.clock = clock
            return old
        }
        old?.invalidate()
        render()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let window { displayProbe.frame = convert(window.bounds, from: window) }
        let scale = traitCollection.displayScale
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if metalLayer.drawableSize != drawableSize {
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = drawableSize
        }
        render()
    }

    private func render() {
        guard let key, HallRenderer.shared != nil, metalLayer.drawableSize.height > 0,
              let meshes = HallMeshStore.shared.meshes(for: key.scene, ready: { [weak self] in self?.render() })
        else { return }
        let prepared = Prepared(key: key, meshes: meshes,
                                pixelScale: metalLayer.drawableSize.height / max(bounds.height, 1),
                                origin: convert(CGPoint.zero, to: nil), screen: window?.bounds.size ?? bounds.size,
                                corner: displayCorner(),
                                motion: motion, phone: phone)
        lock.withLock { self.prepared = prepared }
        requestFrame()
    }

    private func displayCorner() -> CGFloat {
        let radius = displayProbe.effectiveRadius(corner: .topLeft)
        return radius > 0 ? radius : Self.fallbackCorner
    }

    private nonisolated func requestFrame() {
        lock.withLock { clock }?.setNeedsFrame()
    }

    private nonisolated func drawFrame(to drawable: CAMetalDrawable, at time: CFTimeInterval) -> Bool {
        guard let renderer = HallRenderer.shared, let prepared = lock.withLock({ prepared }) else { return false }
        let key = prepared.key
        var args = HallShaderArgs(scene: key.scene, sample: key.sample, size: key.size, frameTop: key.frameTop,
                                  frameBottom: key.frameBottom, sway: prepared.motion?.sway ?? .zero,
                                  scale: prepared.pixelScale, picture: key.picture,
                                  spinnerTime: key.isWaiting ? Float(time.truncatingRemainder(dividingBy: 1000)) : nil)
        prepared.phone?.setGeometry(HallPhone.Geometry(
            view: SIMD2(Float(key.size.width), Float(key.size.height)),
            origin: SIMD2(Float(prepared.origin.x), Float(prepared.origin.y)),
            screen: SIMD2(Float(prepared.screen.width), Float(prepared.screen.height)),
            corner: Float(prepared.corner)))
        let state = prepared.phone?.pose(at: time)
        var phone = state?.pose.map { pose in
            HallPhoneDraw(pose: pose, hall: args,
                          viewSize: SIMD2(Float(key.size.width), Float(key.size.height)), pixelScale: Float(prepared.pixelScale))
        }
        args.glow.x = state?.pose?.settings.screenBloom ?? 0
        if let draw = phone {
            args.glow.y = draw.veil
            prepared.phone?.show(draw.shownPoint, layout: draw.layout)
            let slow = state?.pose?.settings.slowFinder == true && state?.pose?.isTurning == false
            phone = finder(draw, at: time, slow: slow)
        }
        renderer.present(HallRenderer.Frame(sample: key.sample, scene: key.scene, args: args, meshes: prepared.meshes,
                                            picture: key.picture, phone: phone),
                         to: drawable)
        return key.isWaiting || state?.isAnimating == true
    }

    private nonisolated func finder(_ draw: HallPhoneDraw, at time: CFTimeInterval, slow: Bool) -> HallPhoneDraw {
        lock.withLock {
            if slow, draw.screenOn > 0.001, let last = lastFinder, time - last.time < Self.slowFinderInterval {
                return draw.reusingLens(of: last.draw)
            }
            lastFinder = draw.screenOn > 0.001 ? (time, draw) : nil
            return draw
        }
    }
}
