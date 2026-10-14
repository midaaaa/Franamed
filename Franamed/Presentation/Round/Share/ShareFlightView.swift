//
//  ShareFlightView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import MetalKit
import UIKit

final class ShareFlightView: UIView {
    private let body = UIView()
    private let shadow = UIImageView()
    private let renderer: FlipRenderer.Coordinator
    private let metalView: MTKView
    private let litLighting: FlipLighting
    private let litTilt: Double
    private let entering: Bool
    private let stubWidth: CGFloat

    private static let arcLift: CGFloat = 80
    private static let arcTilt: CGFloat = 12 * .pi / 180

    init(flight: FlipFlight, shareFace: MTLTexture?, shadow image: UIImage?, entering: Bool) {
        renderer = flight.coordinator
        metalView = flight.view
        litLighting = renderer.lighting
        litTilt = renderer.tilt
        self.entering = entering
        let stub = renderer.stubSize
        stubWidth = max(stub.width, 1)
        let canvas = CGSize(width: stub.width + FlipLook.canvasPadding * 2, height: stub.height + FlipLook.canvasPadding * 2)
        super.init(frame: CGRect(origin: .zero, size: canvas))
        isUserInteractionEnabled = false
        renderer.blendTexture = shareFace
        body.frame = bounds
        addSubview(body)
        shadow.image = image
        shadow.bounds.size = image?.size ?? .zero
        shadow.center = CGPoint(x: bounds.midX, y: bounds.midY)
        body.addSubview(shadow)
        metalView.frame = bounds
        body.addSubview(metalView)
        layer.zPosition = 1000
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func land() {
        shadow.isHidden = true
    }

    func update(progress p: CGFloat, source: CGRect, target: CGRect, angle: CGFloat, turnsFromBack: Bool) {
        let w = 1 - (1 - p) * (1 - p)
        let arc = sin(p * .pi) * (1 - p)
        let scale = 1 + (target.width / stubWidth - 1) * w
        let center = CGPoint(x: source.midX + (target.midX - source.midX) * w,
                             y: source.midY + (target.midY - source.midY) * w - arc * Self.arcLift)
        let turn = turnsFromBack ? Double.pi * Double(1 - p * p * (3 - 2 * p)) : 0
        let tilt = angle * w + arc * Self.arcTilt
        let face = Float(min(max(p * 1.6 - 0.3, 0), 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = center
        body.transform = CGAffineTransform(rotationAngle: tilt).scaledBy(x: scale, y: scale)
        shadow.alpha = min(max((p - 0.5) / 0.4, 0), 1)
        shadow.transform = CGAffineTransform(scaleX: max(abs(CGFloat(cos(turn))), 0.001), y: 1)
        CATransaction.commit()

        let light = entering ? 0 : 1 - Float(w)
        renderer.lighting = FlipLighting(tint: litLighting.tint, amount: litLighting.amount * light,
                                         exposure: 1 + (litLighting.exposure - 1) * light,
                                         sheenScale: 1 + (litLighting.sheenScale - 1) * light)
        renderer.tilt = litTilt * Double(light)
        renderer.angleOverride = turn
        renderer.faceBlend = renderer.blendTexture == nil ? 0 : face
        metalView.draw()
    }
}
