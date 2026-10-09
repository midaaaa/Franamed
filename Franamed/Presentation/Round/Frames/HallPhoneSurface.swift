//
//  HallPhoneSurface.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import SwiftUI
import UIKit

struct HallPhoneSurface: UIViewRepresentable {
    let phone: HallPhone
    var frameTop: CGFloat = 0
    let frameHeight: CGFloat
    let onToggleOrientation: () -> Void
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        let frameTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.frameTapped(_:)))
        let phoneTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.phoneTapped(_:)))
        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.phoneDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        phoneTap.require(toFail: doubleTap)
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        let rotation = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.rotated(_:)))
        coordinator.frameTap = frameTap
        coordinator.phoneTap = phoneTap
        coordinator.doubleTap = doubleTap
        for gesture in [frameTap, phoneTap, doubleTap, pan, pinch, rotation] as [UIGestureRecognizer] {
            gesture.delegate = coordinator
            view.addGestureRecognizer(gesture)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var surface: HallPhoneSurface
        weak var frameTap: UITapGestureRecognizer?
        weak var phoneTap: UITapGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?

        init(surface: HallPhoneSurface) {
            self.surface = surface
        }

        private var phone: HallPhone { surface.phone }

        private func home(in view: UIView) -> CGPoint {
            view.convert(CGPoint(x: view.bounds.midX, y: surface.frameTop + surface.frameHeight * 0.8), to: nil)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let onPhone = phone.contains(touch.location(in: nil))
            if gesture === frameTap {
                guard let view = gesture.view, !onPhone else { return false }
                let y = touch.location(in: view).y
                return (surface.frameTop..<surface.frameTop + surface.frameHeight).contains(y)
            }
            if gesture === phoneTap { return onPhone }
            if gesture is UIPanGestureRecognizer { return onPhone }
            return onPhone && phone.isHeld
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let continuous: (UIGestureRecognizer) -> Bool = {
                $0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer
            }
            return continuous(gesture) && continuous(other)
        }

        @objc func frameTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            if gesture.location(in: view).x < view.bounds.midX { surface.onTapPrevious() } else { surface.onTapNext() }
        }

        @objc func phoneTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            if phone.isHeld { phone.cycleZoom() } else { phone.raise(to: home(in: view)) }
        }

        @objc func phoneDoubleTapped(_ gesture: UITapGestureRecognizer) {
            surface.onToggleOrientation()
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                if !phone.isHeld { phone.raise(grabbing: gesture.location(in: nil)) }
                phone.drag(by: gesture.translation(in: nil))
            case .changed:
                phone.drag(by: gesture.translation(in: nil))
            default:
                phone.endDrag(velocity: gesture.velocity(in: nil))
            }
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began, .changed: phone.pinch(gesture.scale, ended: false)
            default: phone.pinch(gesture.scale, ended: true)
            }
        }

        @objc func rotated(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                phone.twist(gesture.rotation)
            default:
                if phone.endTwist() { surface.onToggleOrientation() }
            }
        }
    }
}
