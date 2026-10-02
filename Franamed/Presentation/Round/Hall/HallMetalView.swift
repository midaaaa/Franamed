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
    let motion: HallMotion

    func makeUIView(context: Context) -> HallLayerView {
        HallLayerView()
    }

    func updateUIView(_ view: HallLayerView, context: Context) {
        view.motion = motion
        view.key = HallLayerView.Key(sample: sample, scene: scene, size: size, frameTop: frameTop,
                                     frameBottom: frameBottom)
    }

    static func dismantleUIView(_ view: HallLayerView, coordinator: ()) {
        view.motion = nil
    }
}

final class HallLayerView: UIView {
    struct Key: Equatable {
        let sample: HallFrameSample
        let scene: HallScene
        let size: CGSize
        let frameTop: CGFloat
        let frameBottom: CGFloat
    }

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var key: Key? {
        didSet { if key != oldValue { render() } }
    }

    weak var motion: HallMotion? {
        didSet {
            guard motion !== oldValue else { return }
            oldValue?.onSway = nil
            motion?.onSway = { [weak self] _ in self?.render() }
        }
    }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        metalLayer.device = HallRenderer.shared?.device
        metalLayer.pixelFormat = .bgra8Unorm
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard metalLayer.drawableSize != drawableSize else { return }
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = drawableSize
        render()
    }

    private func render() {
        guard let key, let renderer = HallRenderer.shared, metalLayer.drawableSize.height > 0,
              let meshes = HallMeshStore.shared.meshes(for: key.scene, ready: { [weak self] in self?.render() })
        else { return }
        let pixelScale = metalLayer.drawableSize.height / max(bounds.height, 1)
        let args = HallShaderArgs(scene: key.scene, sample: key.sample, size: key.size, frameTop: key.frameTop,
                                  frameBottom: key.frameBottom, sway: motion?.sway ?? .zero, scale: pixelScale)
        renderer.submit(HallRenderer.Frame(sample: key.sample, scene: key.scene, args: args, meshes: meshes),
                        to: HallRenderer.LayerBox(layer: metalLayer))
    }
}
